#import "TSAppDelegate.h"
#import "TSApplicationsManager.h"
#import "TSAppInfo.h"
#import "TSRootViewController.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

static const uint16_t kTrollStoreAPIPort = 48765;
static const NSUInteger kTrollStoreAPIHeaderLimit = 64 * 1024;

@interface TSHTTPResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSDictionary* payload;
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode payload:(NSDictionary*)payload;
@end

@implementation TSHTTPResponse
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode payload:(NSDictionary*)payload
{
	TSHTTPResponse* response = [TSHTTPResponse new];
	response.statusCode = statusCode;
	response.payload = payload ?: @{};
	return response;
}
@end

static BOOL TSBoolValue(NSString* value)
{
	if(value.length == 0) return NO;
	NSString* normalized = value.lowercaseString;
	return [@[@"1", @"true", @"yes", @"on"] containsObject:normalized];
}

static NSString* TSReasonPhrase(NSInteger statusCode)
{
	switch(statusCode)
	{
		case 200: return @"OK";
		case 400: return @"Bad Request";
		case 404: return @"Not Found";
		case 405: return @"Method Not Allowed";
		case 413: return @"Payload Too Large";
		default: return @"Internal Server Error";
	}
}

static NSDictionary<NSString*, NSString*>* TSQueryParametersFromTarget(NSString* target, NSString** pathOut)
{
	NSString* rawTarget = target.length > 0 ? target : @"/";
	NSURLComponents* components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"http://localhost%@", rawTarget]];
	if(pathOut)
	{
		*pathOut = components.path.length > 0 ? components.path : @"/";
	}

	NSMutableDictionary<NSString*, NSString*>* query = [NSMutableDictionary new];
	for(NSURLQueryItem* item in components.queryItems ?: @[])
	{
		query[item.name] = item.value ?: @"";
	}
	return query.copy;
}

static NSString* TSSafeUploadFilename(NSString* requestedFilename)
{
	NSString* candidate = requestedFilename.lastPathComponent;
	if(candidate.length == 0)
	{
		candidate = @"upload.ipa";
	}
	if(![candidate.pathExtension.lowercaseString isEqualToString:@"ipa"])
	{
		candidate = [candidate stringByAppendingPathExtension:@"ipa"];
	}
	return candidate;
}

static void TSWriteAll(int fd, const void* bytes, size_t length)
{
	const uint8_t* cursor = bytes;
	size_t remaining = length;
	while(remaining > 0)
	{
		ssize_t written = send(fd, cursor, remaining, 0);
		if(written <= 0) break;
		cursor += written;
		remaining -= written;
	}
}

@interface TSTrollStoreAPIServer : NSObject
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
+ (instancetype)sharedInstance;
- (BOOL)start:(NSError**)error;
@end

@implementation TSTrollStoreAPIServer

+ (instancetype)sharedInstance
{
	static TSTrollStoreAPIServer* sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [TSTrollStoreAPIServer new];
		sharedInstance.listenFD = -1;
		sharedInstance.serverQueue = dispatch_queue_create("com.iosbuildlab.trollstore-api", DISPATCH_QUEUE_SERIAL);
	});
	return sharedInstance;
}

- (BOOL)start:(NSError**)error
{
	if(self.listenFD >= 0) return YES;

	int listenFD = socket(AF_INET, SOCK_STREAM, 0);
	if(listenFD < 0)
	{
		if(error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		return NO;
	}

	int reuse = 1;
	setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

	struct sockaddr_in address;
	memset(&address, 0, sizeof(address));
	address.sin_len = sizeof(address);
	address.sin_family = AF_INET;
	address.sin_port = htons(kTrollStoreAPIPort);
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

	if(bind(listenFD, (struct sockaddr*)&address, sizeof(address)) != 0)
	{
		NSError* bindError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		close(listenFD);
		if(error) *error = bindError;
		return NO;
	}

	if(listen(listenFD, 8) != 0)
	{
		NSError* listenError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		close(listenFD);
		if(error) *error = listenError;
		return NO;
	}

	self.listenFD = listenFD;
	dispatch_async(self.serverQueue, ^{
		[self acceptLoop];
	});
	return YES;
}

- (void)acceptLoop
{
	while(self.listenFD >= 0)
	{
		int clientFD = accept(self.listenFD, NULL, NULL);
		if(clientFD < 0)
		{
			if(errno == EINTR) continue;
			NSLog(@"[TrollStoreAPI] accept failed: %d", errno);
			break;
		}

		@autoreleasepool
		{
			[self handleClient:clientFD];
		}
		close(clientFD);
	}
}

- (void)handleClient:(int)clientFD
{
	NSMutableData* receivedData = [NSMutableData new];
	NSRange headerRange = NSMakeRange(NSNotFound, 0);
	NSData* delimiter = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];

	while(headerRange.location == NSNotFound && receivedData.length <= kTrollStoreAPIHeaderLimit)
	{
		uint8_t buffer[4096];
		ssize_t bytesRead = recv(clientFD, buffer, sizeof(buffer), 0);
		if(bytesRead <= 0)
		{
			return;
		}

		[receivedData appendBytes:buffer length:(NSUInteger)bytesRead];
		headerRange = [receivedData rangeOfData:delimiter options:0 range:NSMakeRange(0, receivedData.length)];
	}

	if(headerRange.location == NSNotFound)
	{
		[self sendResponse:[TSHTTPResponse responseWithStatusCode:413 payload:@{@"ok": @NO, @"message": @"Header too large or incomplete request."}] toClient:clientFD];
		return;
	}

	NSUInteger headerLength = NSMaxRange(headerRange);
	NSData* headerData = [receivedData subdataWithRange:NSMakeRange(0, headerLength)];
	NSString* headerString = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
	if(headerString.length == 0)
	{
		[self sendResponse:[TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"Invalid request header encoding."}] toClient:clientFD];
		return;
	}

	NSArray<NSString*>* lines = [headerString componentsSeparatedByString:@"\r\n"];
	if(lines.count == 0)
	{
		[self sendResponse:[TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"Missing request line."}] toClient:clientFD];
		return;
	}

	NSArray<NSString*>* requestLineParts = [lines.firstObject componentsSeparatedByString:@" "];
	if(requestLineParts.count < 2)
	{
		[self sendResponse:[TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"Malformed request line."}] toClient:clientFD];
		return;
	}

	NSString* method = requestLineParts[0].uppercaseString;
	NSString* target = requestLineParts[1];

	NSMutableDictionary<NSString*, NSString*>* headers = [NSMutableDictionary new];
	for(NSUInteger lineIndex = 1; lineIndex < lines.count; lineIndex++)
	{
		NSString* line = lines[lineIndex];
		if(line.length == 0) continue;
		NSRange separatorRange = [line rangeOfString:@":"];
		if(separatorRange.location == NSNotFound) continue;

		NSString* key = [[line substringToIndex:separatorRange.location] lowercaseString];
		NSString* value = [[line substringFromIndex:separatorRange.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		headers[key] = value;
	}

	NSString* path = nil;
	NSDictionary<NSString*, NSString*>* query = TSQueryParametersFromTarget(target, &path);
	NSUInteger contentLength = (NSUInteger)MAX(headers[@"content-length"].integerValue, 0);
	NSData* bodyPrefix = receivedData.length > headerLength ? [receivedData subdataWithRange:NSMakeRange(headerLength, receivedData.length - headerLength)] : [NSData data];

	NSString* uploadFilePath = nil;
	if([path isEqualToString:@"/install"] && [method isEqualToString:@"POST"])
	{
		NSError* uploadError = nil;
		uploadFilePath = [self receiveUploadFromClient:clientFD initialBody:bodyPrefix contentLength:contentLength suggestedFilename:query[@"filename"] error:&uploadError];
		if(!uploadFilePath)
		{
			NSString* message = uploadError.localizedDescription ?: @"Failed to receive IPA upload.";
			[self sendResponse:[TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": message}] toClient:clientFD];
			return;
		}
	}

	TSHTTPResponse* response = [self routeMethod:method path:path query:query uploadFilePath:uploadFilePath];
	[self sendResponse:response toClient:clientFD];

	if(uploadFilePath)
	{
		[[NSFileManager defaultManager] removeItemAtPath:uploadFilePath error:nil];
	}
}

- (NSString*)receiveUploadFromClient:(int)clientFD initialBody:(NSData*)initialBody contentLength:(NSUInteger)contentLength suggestedFilename:(NSString*)suggestedFilename error:(NSError**)error
{
	if(contentLength == 0)
	{
		if(error) *error = [NSError errorWithDomain:@"TrollStoreAPI" code:400 userInfo:@{NSLocalizedDescriptionKey : @"POST /install requires a non-empty IPA request body."}];
		return nil;
	}

	NSString* filename = TSSafeUploadFilename(suggestedFilename);
	NSString* tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, filename]];
	[[NSFileManager defaultManager] createFileAtPath:tempPath contents:nil attributes:nil];
	NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:tempPath];
	if(!handle)
	{
		if(error) *error = [NSError errorWithDomain:@"TrollStoreAPI" code:500 userInfo:@{NSLocalizedDescriptionKey : @"Failed to create temporary IPA file."}];
		return nil;
	}

	NSUInteger bytesRemaining = contentLength;
	NSUInteger initialLength = MIN(bytesRemaining, initialBody.length);
	if(initialLength > 0)
	{
		[handle writeData:[initialBody subdataWithRange:NSMakeRange(0, initialLength)]];
		bytesRemaining -= initialLength;
	}

	while(bytesRemaining > 0)
	{
		uint8_t buffer[64 * 1024];
		size_t chunkSize = MIN(bytesRemaining, sizeof(buffer));
		ssize_t bytesRead = recv(clientFD, buffer, chunkSize, 0);
		if(bytesRead <= 0)
		{
			[handle closeFile];
			[[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
			if(error) *error = [NSError errorWithDomain:@"TrollStoreAPI" code:400 userInfo:@{NSLocalizedDescriptionKey : @"IPA upload ended before Content-Length was fully received."}];
			return nil;
		}
		[handle writeData:[NSData dataWithBytes:buffer length:(NSUInteger)bytesRead]];
		bytesRemaining -= (NSUInteger)bytesRead;
	}

	[handle closeFile];
	return tempPath;
}

- (TSHTTPResponse*)routeMethod:(NSString*)method path:(NSString*)path query:(NSDictionary<NSString*, NSString*>*)query uploadFilePath:(NSString*)uploadFilePath
{
	if([method isEqualToString:@"GET"] && [path isEqualToString:@"/health"])
	{
		NSDictionary* payload = @{
			@"ok": @YES,
			@"service": @"trollstore-local-api",
			@"port": @(kTrollStoreAPIPort),
			@"listen_address": @"127.0.0.1",
			@"frontmost_required": @YES,
			@"app_version": [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown"
		};
		return [TSHTTPResponse responseWithStatusCode:200 payload:payload];
	}

	if([method isEqualToString:@"GET"] && [path isEqualToString:@"/apps"])
	{
		return [TSHTTPResponse responseWithStatusCode:200 payload:[self installedAppsPayload]];
	}

	if([method isEqualToString:@"POST"] && [path isEqualToString:@"/install"])
	{
		return [self installResponseForUploadedIPA:uploadFilePath query:query];
	}

	if([method isEqualToString:@"POST"] && [path isEqualToString:@"/uninstall"])
	{
		return [self uninstallResponseForQuery:query];
	}

	if([method isEqualToString:@"POST"] && [path isEqualToString:@"/open"])
	{
		return [self openResponseForQuery:query];
	}

	if([@[@"/health", @"/apps", @"/install", @"/uninstall", @"/open"] containsObject:path])
	{
		return [TSHTTPResponse responseWithStatusCode:405 payload:@{@"ok": @NO, @"message": @"Unsupported HTTP method for this endpoint."}];
	}

	return [TSHTTPResponse responseWithStatusCode:404 payload:@{@"ok": @NO, @"message": @"Unknown endpoint."}];
}

- (NSDictionary*)installedAppsPayload
{
	TSApplicationsManager* manager = [TSApplicationsManager sharedInstance];
	NSMutableArray* apps = [NSMutableArray new];

	for(NSString* appPath in [manager installedAppPaths])
	{
		TSAppInfo* appInfo = [[TSAppInfo alloc] initWithAppBundlePath:appPath];
		NSError* error = [appInfo sync_loadBasicInfo];
		NSMutableDictionary* appPayload = [NSMutableDictionary dictionaryWithObject:appPath ?: @"" forKey:@"path"];

		if(error)
		{
			appPayload[@"ok"] = @NO;
			appPayload[@"error"] = error.localizedDescription ?: @"Failed to load app info.";
		}
		else
		{
			appPayload[@"ok"] = @YES;
			appPayload[@"name"] = [appInfo displayName] ?: @"";
			appPayload[@"bundle_id"] = [appInfo bundleIdentifier] ?: @"";
			appPayload[@"version"] = [appInfo versionString] ?: @"";
			appPayload[@"registration_state"] = [appInfo registrationState] ?: @"";
			appPayload[@"debuggable"] = @([appInfo isDebuggable]);
		}
		[apps addObject:appPayload];
	}

	return @{
		@"ok": @YES,
		@"count": @(apps.count),
		@"apps": apps
	};
}

- (TSHTTPResponse*)installResponseForUploadedIPA:(NSString*)uploadFilePath query:(NSDictionary<NSString*, NSString*>*)query
{
	if(uploadFilePath.length == 0)
	{
		return [TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"Missing uploaded IPA file."}];
	}

	BOOL force = TSBoolValue(query[@"force"]);
	NSString* installLog = nil;
	TSApplicationsManager* manager = [TSApplicationsManager sharedInstance];
	int code = [manager installIpa:uploadFilePath force:force log:&installLog];
	NSString* message = code == 0 ? @"Installed successfully." : [manager errorForCode:code].localizedDescription ?: @"Install failed.";

	NSMutableDictionary* payload = [@{
		@"ok": @(code == 0),
		@"code": @(code),
		@"message": message,
		@"force": @(force),
		@"uploaded_filename": uploadFilePath.lastPathComponent ?: @""
	} mutableCopy];
	if(installLog.length > 0)
	{
		payload[@"log"] = installLog;
	}

	return [TSHTTPResponse responseWithStatusCode:(code == 0 ? 200 : 400) payload:payload];
}

- (TSHTTPResponse*)uninstallResponseForQuery:(NSDictionary<NSString*, NSString*>*)query
{
	NSString* bundleID = query[@"bundle_id"] ?: query[@"app_id"];
	if(bundleID.length == 0)
	{
		return [TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"bundle_id is required."}];
	}

	TSApplicationsManager* manager = [TSApplicationsManager sharedInstance];
	int code = [manager uninstallApp:bundleID];
	NSString* message = code == 0 ? @"Uninstalled successfully." : [manager errorForCode:code].localizedDescription ?: @"Uninstall failed.";

	return [TSHTTPResponse responseWithStatusCode:(code == 0 ? 200 : 400) payload:@{
		@"ok": @(code == 0),
		@"code": @(code),
		@"bundle_id": bundleID,
		@"message": message
	}];
}

- (TSHTTPResponse*)openResponseForQuery:(NSDictionary<NSString*, NSString*>*)query
{
	NSString* bundleID = query[@"bundle_id"] ?: query[@"app_id"];
	if(bundleID.length == 0)
	{
		return [TSHTTPResponse responseWithStatusCode:400 payload:@{@"ok": @NO, @"message": @"bundle_id is required."}];
	}

	BOOL success = [[TSApplicationsManager sharedInstance] openApplicationWithBundleID:bundleID];
	return [TSHTTPResponse responseWithStatusCode:(success ? 200 : 400) payload:@{
		@"ok": @(success),
		@"bundle_id": bundleID,
		@"message": success ? @"Open request dispatched." : @"Failed to open application."
	}];
}

- (void)sendResponse:(TSHTTPResponse*)response toClient:(int)clientFD
{
	NSError* serializationError = nil;
	NSData* bodyData = [NSJSONSerialization dataWithJSONObject:response.payload ?: @{} options:NSJSONWritingPrettyPrinted error:&serializationError];
	if(!bodyData)
	{
		NSDictionary* fallbackPayload = @{@"ok": @NO, @"message": serializationError.localizedDescription ?: @"Failed to encode JSON response."};
		bodyData = [NSJSONSerialization dataWithJSONObject:fallbackPayload options:0 error:nil];
		response = [TSHTTPResponse responseWithStatusCode:500 payload:fallbackPayload];
	}

	NSString* header = [NSString stringWithFormat:
		@"HTTP/1.1 %ld %@\r\n"
		@"Content-Type: application/json; charset=utf-8\r\n"
		@"Content-Length: %lu\r\n"
		@"Connection: close\r\n"
		@"\r\n",
		(long)response.statusCode,
		TSReasonPhrase(response.statusCode),
		(unsigned long)bodyData.length];

	NSData* headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
	TSWriteAll(clientFD, headerData.bytes, headerData.length);
	TSWriteAll(clientFD, bodyData.bytes, bodyData.length);
}

@end

@implementation TSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSError* apiError = nil;
	if([[TSTrollStoreAPIServer sharedInstance] start:&apiError])
	{
		NSLog(@"[TrollStoreAPI] listening on 127.0.0.1:%d", kTrollStoreAPIPort);
	}
	else
	{
		NSLog(@"[TrollStoreAPI] failed to start: %@", apiError);
	}
	return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options
{
	return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions
{
}

@end
