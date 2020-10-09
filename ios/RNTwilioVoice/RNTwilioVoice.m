//
//  TwilioVoice.m
//

#import "RNTwilioVoice.h"
#import <React/RCTLog.h>

@import AVFoundation;
@import PushKit;
@import CallKit;
@import TwilioVoice;

@interface RNTwilioVoice () <PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, CXProviderDelegate>
    @property (nonatomic, strong) NSString *deviceTokenString;
    
    @property (nonatomic, strong) PKPushRegistry *voipRegistry;
    @property (nonatomic, strong) TVOCallInvite *callInvite;
    @property (nonatomic, strong) void(^incomingPushCompletionCallback)(void);
    @property (nonatomic, strong) TVOCall *call;
    @property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;
    @property (nonatomic, strong) void(^callKitCompletionCallback)(BOOL);
    @property (nonatomic, strong) CXProvider *callKitProvider;
    @property (nonatomic, strong) CXCallController *callKitCallController;
    @property (nonatomic, assign) BOOL userInitiatedDisconnect;
    @end

@implementation RNTwilioVoice {
    NSMutableDictionary *_settings;
    NSMutableDictionary *_callParams;
    NSString *_tokenUrl;
    NSString *_token;
}
    
    NSString * const StatePending = @"PENDING";
    NSString * const StateRinging = @"RINGING";
    NSString * const StateConnecting = @"CONNECTING";
    NSString * const StateConnected = @"CONNECTED";
    NSString * const StateReconnecting = @"RECONNECTING";
    NSString * const StateReconnected = @"RECONNECTED";
    NSString * const StateDisconnected = @"DISCONNECTED";
    NSString * const StateRejected = @"REJECTED";
    
- (dispatch_queue_t)methodQueue
    {
        return dispatch_get_main_queue();
    }
    
    RCT_EXPORT_MODULE()
    
- (NSArray<NSString *> *)supportedEvents
    {
      return @[@"connectionDidConnect", @"connectionDidDisconnect", @"callRejected", @"deviceReady", @"deviceNotReady", @"connectionIsReconnecting", @"connectionDidReconnect", @"connectionIsRinging"];
    }
    
    @synthesize bridge = _bridge;
    
- (void)dealloc {
    if (self.callKitProvider) {
        [self.callKitProvider invalidate];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
    
    RCT_EXPORT_METHOD(initWithAccessToken:(NSString *)token) {
        _token = token;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppTerminateNotification) name:UIApplicationWillTerminateNotification object:nil];
        [self initPushRegistry];
    }
    
    RCT_EXPORT_METHOD(initWithAccessTokenUrl:(NSString *)tokenUrl) {
        _tokenUrl = tokenUrl;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppTerminateNotification) name:UIApplicationWillTerminateNotification object:nil];
        [self initPushRegistry];
    }
    
    RCT_EXPORT_METHOD(configureCallKit: (NSDictionary *)params) {
        if (self.callKitCallController == nil) {
            self.audioDevice = [TVODefaultAudioDevice audioDevice];
            TwilioVoice.audioDevice = self.audioDevice;
            _settings = [[NSMutableDictionary alloc] initWithDictionary:params];
            if(![params objectForKey:@"appName"].length == 0) {
                id mutableParams = [params mutableCopy];
                [mutableParams setObject:NSString *appName = [[NSBundle bundleWithIdentifier:@"BundleIdentifier"] objectForInfoDictionaryKey:@"CFBundleExecutable"];
                                  forKey:@"appName"];
                params = [NSDictionary dictionaryWithDictionary:mutableParams];
            }
            
            NSLocalizedStringWithDefaultValue(params[@"appName"], nil, [NSBundle mainBundle], params[@"appName"], @"Application Name.");

            
            CXProviderConfiguration *configuration = [CXProviderConfiguration alloc];
            
            if([[[UIDevice currentDevice] systemVersion] floatValue] >= 14.0) {
                #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
                configuration = [configuration init];
                #else
                configuration = [configuration initWithLocalizedName:params[@"appName"]];
                #endif
            } else {
                configuration = [configuration initWithLocalizedName:params[@"appName"]];
            }

            configuration.maximumCallGroups = 1;
            configuration.maximumCallsPerCallGroup = 1;
            if (_settings[@"imageName"]) {
                configuration.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:_settings[@"imageName"]]);
            }
            if (_settings[@"ringtoneSound"]) {
                configuration.ringtoneSound = _settings[@"ringtoneSound"];
            }
            
            _callKitProvider = [[CXProvider alloc] initWithConfiguration:configuration];
            [_callKitProvider setDelegate:self queue:nil];
            
            NSLog(@"CallKit Initialized");
            
            self.callKitCallController = [[CXCallController alloc] init];
        }
    }
    
    RCT_EXPORT_METHOD(connect: (NSDictionary *)params) {
        NSLog(@"Calling phone number %@", [params valueForKey:@"To"]);
        
        //  [TwilioVoice setLogLevel:TVOLogLevelVerbose];
        
        UIDevice* device = [UIDevice currentDevice];
        device.proximityMonitoringEnabled = YES;
        self.audioDevice = [TVODefaultAudioDevice audioDevice];
        TwilioVoice.audioDevice = self.audioDevice;
        if (self.call && self.call.state == TVOCallStateConnected) {
            [self.call disconnect];
        } else {
            NSUUID *uuid = [NSUUID UUID];
            NSString *handle = [params valueForKey:@"To"];
            _callParams = [[NSMutableDictionary alloc] initWithDictionary:params];
            [self performStartCallActionWithUUID:uuid handle:handle];
        }
    }
    
    RCT_EXPORT_METHOD(disconnect) {
        NSLog(@"Disconnecting call");
        [self performEndCallActionWithUUID:self.call.uuid];
    }
    
    RCT_EXPORT_METHOD(setMuted: (BOOL *)muted) {
        NSLog(@"Mute/UnMute call");
        self.call.muted = muted;
    }
    
    RCT_EXPORT_METHOD(setSpeakerPhone: (BOOL *)speaker) {
        [self toggleAudioRoute:speaker];
    }
    
    RCT_EXPORT_METHOD(sendDigits: (NSString *)digits){
        if (self.call && self.call.state == TVOCallStateConnected) {
            NSLog(@"SendDigits %@", digits);
            [self.call sendDigits:digits];
        }
    }
    
    RCT_EXPORT_METHOD(unregister){
        NSLog(@"unregister");
        NSString *accessToken = [self fetchAccessToken];
        
        [TwilioVoice unregisterWithAccessToken:accessToken
                                   deviceToken:self.deviceTokenString
                                    completion:^(NSError * _Nullable error) {
                                        if (error) {
                                            NSLog(@"An error occurred while unregistering: %@", [error localizedDescription]);
                                        } else {
                                            NSLog(@"Successfully unregistered for VoIP push notifications.");
                                        }
                                    }];
        
        self.deviceTokenString = nil;
    }
    
    RCT_REMAP_METHOD(getActiveCall,
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject){
        NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
        if (self.callInvite) {
            if (self.callInvite.callSid){
                [params setObject:self.callInvite.callSid forKey:@"call_sid"];
            }
            if (self.callInvite.from){
                [params setObject:self.callInvite.from forKey:@"from"];
            }
            if (self.callInvite.to){
                [params setObject:self.callInvite.to forKey:@"to"];
            }
            [params setObject:StatePending forKey:@"call_state"];
            resolve(params);
        } else if (self.call) {
            if (self.call.sid) {
                [params setObject:self.call.sid forKey:@"call_sid"];
            }
            if (self.call.to){
                [params setObject:self.call.to forKey:@"call_to"];
            }
            if (self.call.from){
                [params setObject:self.call.from forKey:@"call_from"];
            }
            if (self.call.state == TVOCallStateConnected) {
                [params setObject:StateConnected forKey:@"call_state"];
            } else if (self.call.state == TVOCallStateConnecting) {
                [params setObject:StateConnecting forKey:@"call_state"];
            } else if (self.call.state == TVOCallStateDisconnected) {
                [params setObject:StateDisconnected forKey:@"call_state"];
            }
            resolve(params);
        } else{
            reject(@"no_call", @"There was no active call", nil);
        }
    }
    
- (void)initPushRegistry {
    NSLog(@"initPushRegistry called");
    self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    self.voipRegistry.delegate = self;
    self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}
    
- (NSString *)fetchAccessToken {
    if (_tokenUrl) {
        NSString *accessToken = [NSString stringWithContentsOfURL:[NSURL URLWithString:_tokenUrl]
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
        return accessToken;
    } else {
        return _token;
    }
}
    
#pragma mark - PKPushRegistryDelegate
- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    NSLog(@"pushRegistry:didUpdatePushCredentials:forType");

    if ([type isEqualToString:PKPushTypeVoIP]) {
        const unsigned *tokenBytes = [credentials.token bytes];
        self.deviceTokenString = [NSString stringWithFormat:@"<%08x %08x %08x %08x %08x %08x %08x %08x>", 
                                                        ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                                                        ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                                                        ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

        NSString *accessToken = [self fetchAccessToken];
        
        [TwilioVoice registerWithAccessToken:accessToken
                                 deviceToken:self.deviceTokenString
                                  completion:^(NSError *error) {
                                      if (error) {
                                          NSLog(@"An error occurred while registering: %@", [error localizedDescription]);
                                          NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
                                          [params setObject:[error localizedDescription] forKey:@"err"];
                                          
                                          [self sendEventWithName:@"deviceNotReady" body:params];
                                      } else {
                                          NSLog(@"Successfully registered for VoIP push notifications.");
                                          [self sendEventWithName:@"deviceReady" body:nil];
                                      }
                                  }];
    }
}
    
- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {
    NSLog(@"pushRegistry:didInvalidatePushTokenForType");
    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        NSString *accessToken = [self fetchAccessToken];
        
        [TwilioVoice unregisterWithAccessToken:accessToken
                                   deviceToken:self.deviceTokenString
                                    completion:^(NSError * _Nullable error) {
                                        if (error) {
                                            NSLog(@"An error occurred while unregistering: %@", [error localizedDescription]);
                                        } else {
                                            NSLog(@"Successfully unregistered for VoIP push notifications.");
                                        }
                                    }];
        
        self.deviceTokenString = nil;
    }
}
    
/**
 * This delegate method is available on iOS 11 and above. Call the completion handler once the
 * notification payload is passed to the `TwilioVoice.handleNotification()` method.
 */
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type withCompletionHandler:(void (^)(void))completion {
    

    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:");

    
    if ([payload.dictionaryPayload[@"twi_message_type"] isEqualToString:@"twilio.voice.cancel"]) {
        CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:@"alice"];

        CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
        callUpdate.remoteHandle = callHandle;
        callUpdate.supportsDTMF = YES;
        callUpdate.supportsHolding = YES;
        callUpdate.supportsGrouping = NO;
        callUpdate.supportsUngrouping = NO;
        callUpdate.hasVideo = NO;

        NSUUID *uuid = [NSUUID UUID];

        [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {

            if (error) {
              NSLog(@"Failed to report incoming call successfully: %@.", [error localizedDescription]);
            } else {
              NSLog(@"Incoming call successfully reported");
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
            CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

            [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
                if (error) {
                  NSLog(@"requestTransaction request failed: %@", [error localizedDescription]);
                } else {
                  NSLog(@"requestTransaction transaction request successful");
                }
            }];
        });

        return;
    }

    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue: Nil]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
}
    
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
             forType:(PKPushType)type
{
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:");
    
    if ([type isEqualToString:PKPushTypeVoIP]) {
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue: Nil]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
}
    
- (void)incomingPushHandled {
    if (self.incomingPushCompletionCallback) {
        self.incomingPushCompletionCallback();
        self.incomingPushCompletionCallback = nil;
    }
}
    
#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {
    NSLog(@"callInviteReceived:");
    if (self.callInvite) {
        NSLog(@"Already a pending incoming call invite.");
        NSLog(@"  >> Ignoring call from %@", callInvite.from);
        [self incomingPushHandled];
        return;
    } else if (self.call) {
        NSLog(@"Already an active call.");
        NSLog(@"  >> Ignoring call from %@", callInvite.from);
        [self incomingPushHandled];
        return;
    }
    
    self.callInvite = callInvite;
    
    [self reportIncomingCallFrom:callInvite.from withUUID:callInvite.uuid];
}
    
    
- (void)cancelledCallInviteReceived:(TVOCancelledCallInvite *)cancelledCallInvite error:(nonnull NSError *)error {
    NSLog(@"cancelledCallInviteReceived:");
    
    [self incomingPushHandled];
    
    if (!self.callInvite ||
        ![self.callInvite.callSid isEqualToString:cancelledCallInvite.callSid]) {
        NSLog(@"No matching pending CallInvite. Ignoring the Cancelled CallInvite");
        return;
    }
    
    [self performEndCallActionWithUUID:self.callInvite.uuid];
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    if (self.callInvite.callSid){
        [params setObject:self.callInvite.callSid forKey:@"call_sid"];
    }
    
    if (self.callInvite.from){
        [params setObject:self.callInvite.from forKey:@"from"];
    }
    if (self.callInvite.to){
        [params setObject:self.callInvite.to forKey:@"to"];
    }
    [params setObject:StateDisconnected forKey:@"call_state"];
    [self sendEventWithName:@"connectionDidDisconnect" body:params];
    
    self.callInvite = nil;
    [self incomingPushHandled];
}
    
    
- (void)notificationError:(NSError *)error {
    NSLog(@"notificationError: %@", [error localizedDescription]);
}
    
#pragma mark - TVOCallDelegate
- (void)callDidStartRinging:(TVOCall *)call {
    NSLog(@"callDidStartRinging:");
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:call.sid forKey:@"call_sid"];
    [params setObject:StateRinging forKey:@"call_state"];
    
    if (call.from){
        [params setObject:call.from forKey:@"from"];
    }
    if (call.to){
        [params setObject:call.to forKey:@"to"];
    }
    [self sendEventWithName:@"connectionIsRinging" body:params];
    
}
    
- (void)callDidConnect:(TVOCall *)call {
    self.call = call;
    self.callKitCompletionCallback(YES);
    self.callKitCompletionCallback = nil;
    
    NSMutableDictionary *callParams = [[NSMutableDictionary alloc] init];
    [callParams setObject:call.sid forKey:@"call_sid"];
    if (call.state == TVOCallStateConnecting) {
        [callParams setObject:StateConnecting forKey:@"call_state"];
    } else if (call.state == TVOCallStateConnected) {
        [callParams setObject:StateConnected forKey:@"call_state"];
    }
    
    if (call.from){
        [callParams setObject:call.from forKey:@"from"];
    }
    if (call.to){
        [callParams setObject:call.to forKey:@"to"];
    }
    [self sendEventWithName:@"connectionDidConnect" body:callParams];
}
    
- (void)call:(TVOCall *)call isReconnectingWithError:(NSError *)error {
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    if (error) {
        NSString* errMsg = [error localizedDescription];
        if (error.localizedFailureReason) {
            errMsg = [error localizedFailureReason];
        }
        [params setObject:errMsg forKey:@"error"];
    }
    [params setObject:call.sid forKey:@"call_sid"];
    [params setObject:StateReconnecting forKey:@"call_state"];
    
    if (call.from){
        [params setObject:call.from forKey:@"from"];
    }
    if (call.to){
        [params setObject:call.to forKey:@"to"];
    }
    [self sendEventWithName:@"connectionIsReconnecting" body:params];
}
    
- (void)callDidReconnect:(TVOCall *)call {
    NSLog(@"Call reconnected");
    self.call = call;
    self.callKitCompletionCallback(YES);
    self.callKitCompletionCallback = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:call.sid forKey:@"call_sid"];
    [params setObject:StateReconnected forKey:@"call_state"];
    
    if (call.from){
        [params setObject:call.from forKey:@"from"];
    }
    if (call.to){
        [params setObject:call.to forKey:@"to"];
    }
    [self sendEventWithName:@"connectionDidReconnect" body:params];
}
    
- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
    NSLog(@"Call failed to connect: %@", error);
    
    self.callKitCompletionCallback(NO);
    [self performEndCallActionWithUUID:call.uuid];
    [self callDisconnected:error];
}
    
- (void)call:(TVOCall *)call didDisconnectWithError:(NSError *)error {
    NSLog(@"Call disconnected with error: %@", error);
    
    [self performEndCallActionWithUUID:call.uuid];
    [self callDisconnected:error];
}
    
- (void)callDisconnected:(NSError *)error {
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    if (error) {
        NSString* errMsg = [error localizedDescription];
        if (error.localizedFailureReason) {
            errMsg = [error localizedFailureReason];
        }
        [params setObject:errMsg forKey:@"error"];
    }
    if (self.call.sid) {
        [params setObject:self.call.sid forKey:@"call_sid"];
    }
    if (self.call.to){
        [params setObject:self.call.to forKey:@"call_to"];
    }
    if (self.call.from){
        [params setObject:self.call.from forKey:@"call_from"];
    }
    if (self.call.state == TVOCallStateDisconnected) {
        [params setObject:StateDisconnected forKey:@"call_state"];
    }
    [self sendEventWithName:@"connectionDidDisconnect" body:params];
    
    self.call = nil;
    self.callKitCompletionCallback = nil;
    self.userInitiatedDisconnect = NO;
}
    
#pragma mark - AVAudioSession
- (void)toggleAudioRoute: (BOOL *)toSpeaker {
    // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
    self.audioDevice.block =  ^ {
        // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
        kTVODefaultAVAudioSessionConfigurationBlock();
        
        // Overwrite the audio route
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *error = nil;
        if (toSpeaker) {
            if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error]) {
                NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
            }
        } else {
            if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error]) {
                NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
            }
        }
    };
    self.audioDevice.block();}
    
#pragma mark - CXProviderDelegate
- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"providerDidReset");
    self.audioDevice.enabled = YES;
    
}
    
- (void)providerDidBegin:(CXProvider *)provider {
    NSLog(@"providerDidBegin");
}
    
- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didActivateAudioSession");
    self.audioDevice.enabled = YES;
}
    
- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didDeactivateAudioSession");
    self.audioDevice.enabled = NO;
}
    
- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider:timedOutPerformingAction");
}
    
- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider:performStartCallAction");
    
    [self.callKitProvider reportOutgoingCallWithUUID:action.callUUID startedConnectingAtDate:[NSDate date]];
    
    __weak typeof(self) weakSelf = self;
    [self performVoiceCallWithUUID:action.callUUID client:nil completion:^(BOOL success) {
        __strong typeof(self) strongSelf = weakSelf;
        if (success) {
            [strongSelf.callKitProvider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate date]];
            [action fulfill];
        } else {
            [action fail];
        }
    }];
}
    
- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider:performAnswerCallAction");
    NSAssert([self.callInvite.uuid isEqual:action.callUUID], @"We only support one Invite at a time.");
    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    [self performAnswerVoiceCallWithUUID:action.callUUID completion:^(BOOL success) {
        if (success) {
            [action fulfill];
        } else {
            [action fail];
        }
    }];
    
    [action fulfill];
}
    
- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider:performEndCallAction");
    
    if (self.callInvite) {
        [self sendEventWithName:@"callRejected" body:@"callRejected"];
        [self.callInvite reject];
        self.callInvite = nil;
    } else if (self.call) {
        [self.call disconnect];
    }
    
    self.audioDevice.enabled = YES;
    
    [action fulfill];
}
    
- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self.call setOnHold:action.isOnHold];
        [action fulfill];
    } else {
        [action fail];
    }
}
    
#pragma mark - CallKit Actions
- (void)performStartCallActionWithUUID:(NSUUID *)uuid handle:(NSString *)handle {
    if (uuid == nil || handle == nil) {
        return;
    }
    
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:callHandle];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
    
    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"StartCallAction transaction request failed: %@", [error localizedDescription]);
        } else {
            NSLog(@"StartCallAction transaction request successful");
            
            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = YES;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;
            
            [self.callKitProvider reportCallWithUUID:uuid updated:callUpdate];
        }
    }];
}
    
- (void)reportIncomingCallFrom:(NSString *)from withUUID:(NSUUID *)uuid {
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:from];
    
    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = callHandle;
    callUpdate.supportsDTMF = YES;
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.hasVideo = NO;
    
    [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {
        if (!error) {
            NSLog(@"Incoming call successfully reported");
        } else {
            NSLog(@"Failed to report incoming call successfully: %@.", [error localizedDescription]);
        }
    }];
}
    
- (void)performEndCallActionWithUUID:(NSUUID *)uuid {
    if (uuid == nil) {
        return;
    }
    
    UIDevice* device = [UIDevice currentDevice];
    device.proximityMonitoringEnabled = NO;
    
    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];
    
    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"EndCallAction transaction request failed: %@", [error localizedDescription]);
        } else {
            NSLog(@"EndCallAction transaction request successful");
        }
    }];
}
    
- (void)performVoiceCallWithUUID:(NSUUID *)uuid
                          client:(NSString *)client
                      completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:[self fetchAccessToken] block:^(TVOConnectOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.params = _callParams;
        builder.uuid = uuid;
    }];
    self.call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    self.callKitCompletionCallback = completionHandler;
}
    
- (void)performAnswerVoiceCallWithUUID:(NSUUID *)uuid
                            completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOAcceptOptions *acceptOptions = [TVOAcceptOptions optionsWithCallInvite:self.callInvite block:^(TVOAcceptOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.uuid = strongSelf.callInvite.uuid;
    }];
    
    self.call = [self.callInvite acceptWithOptions:acceptOptions delegate:self];
    
    if (!self.call) {
        completionHandler(NO);
    } else {
        self.callKitCompletionCallback = completionHandler;
    }
    
    self.callInvite = nil;
    [self incomingPushHandled];
}
    
- (void)handleAppTerminateNotification {
    NSLog(@"handleAppTerminateNotification called");
    
    if (self.call) {
        NSLog(@"handleAppTerminateNotification disconnecting an active call");
        [self.call disconnect];
    }
}
    
@end
