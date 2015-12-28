//
//  LVHttp.m
//  LVSDK
//
//  Created by dongxicheng on 2/2/15.
//  Copyright (c) 2015 dongxicheng. All rights reserved.
//

#import "LVHttp.h"
#import "LVHttpResponse.h"
#import "LVData.h"
#import "LView.h"
#import "lV.h"
#import "lVauxlib.h"
#import "lVlib.h"
#import "lVstate.h"
#import "lVgc.h"

@interface LVHttp ()<NSURLConnectionDataDelegate>
@property(nonatomic,strong) id mySelf;
@property(nonatomic,strong) LVHttpResponse* response;
@property(nonatomic,strong) id function;
@property(nonatomic,assign) CGFloat timeout;
@property(nonatomic,strong) NSURLConnection* connection;
@end

@implementation LVHttp

static void releaseUserDataHttp(LVUserDataHttp* user){
    if( user && user->http ){
        LVHttp* http = CFBridgingRelease(user->http);
        user->http = NULL;
        if( http ){
            http.userData = NULL;
            http.lview = nil;
        }
    }
}

-(void) dealloc{
}

-(id) init:(lv_State*) l{
    self = [super init];
    if( self ){
        self.lview = (__bridge LView *)(l->lView);
        self.mySelf = self;
        self.function = [[NSMutableString alloc] init];
        self.response = [[LVHttpResponse alloc] init];
        self.timeout = 30.0;
    }
    return self;
}

-(void) requesetEndToDo{
    lv_State* l = self.lview.l;
    if( l ){
        lv_checkStack32(l);
        [LVUtil pushRegistryValue:l key:self];
        [LVUtil call:l lightUserData:self.function key1:"callback" key2:NULL nargs:1];
        [LVUtil unregistry:l key:self];
    }
    self.response = nil;
    self.mySelf = nil;
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}


+(BOOL) isTrustedHost:(NSString*) host{
    NSArray* trustedHosts = @[@".alicdn.com",@".tbcdn.com",@".taobao.com",@".tmall.com",@".juhuasuan.com"];
    for( NSString* host in trustedHosts ) {
        if( [host hasSuffix:host] ) {
            return YES;
        }
    }
    return NO;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ( [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] ){
        if ( [LVHttp isTrustedHost:challenge.protectionSpace.host] ) {
            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
        }
    }
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    self.response.error = error;
    [self performSelectorOnMainThread:@selector(requesetEndToDo) withObject:nil waitUntilDone:NO];
}

-(void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    if( self.response.data == nil ) {
        self.response.data = [[NSMutableData alloc] init];
    }
    [self.response.data appendData:data];
}

-(void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{
    self.response.response = response;
    if( [response isKindOfClass:[NSHTTPURLResponse class]] ){
        self.response.httpResponse = (NSHTTPURLResponse*)response;
    }
}
-(void) connectionDidFinishLoading:(NSURLConnection *)connection{
    [self performSelectorOnMainThread:@selector(requesetEndToDo) withObject:nil waitUntilDone:NO];
}

static int lvNewHttpObject (lv_State *L ) {
    LVHttp* http = [[LVHttp alloc] init:L];
    {
        NEW_USERDATA(userData, LVUserDataHttp);
        userData->http = CFBridgingRetain(http);
        http.userData = userData;
        
        lvL_getmetatable(L, META_TABLE_Http );
        lv_setmetatable(L, -2);
    }
    [LVUtil registryValue:L key:http stack:-1];
    return 1;
}

static int get (lv_State *L) {
    int argN = lv_gettop(L);
    if( argN>=2 ){
        LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
        if(  LVIsType(user,LVUserDataHttp) ) {
            LVHttp* http = (__bridge LVHttp *)(user->http);
            NSString* urlStr = lv_paramString(L, 2);
            
            if( lv_type(L, 3) != LV_TNIL ) {
                [LVUtil registryValue:L key:http.function stack:3];
            }
            NSURL *url = [NSURL URLWithString:urlStr];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [request setHTTPMethod:@"GET"];
            [request setTimeoutInterval:http.timeout];
            
            NSOperationQueue *queue = [[NSOperationQueue alloc]init];
            http.connection = [[NSURLConnection alloc] initWithRequest:request delegate:http];
            [http.connection setDelegateQueue:queue];
            [http.connection start];
        }
    }
    return 0; /* new userdatum is already on the stack */
}

static int post (lv_State *L) {
    int argN = lv_gettop(L);
    if( argN>=3 ){
        LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
        if(  LVIsType(user,LVUserDataHttp) ) {
            // 1:url    2:heads   3:data   4:callback
            NSString* urlStr = lv_paramString(L, 2);
            LVHttp* http = (__bridge LVHttp *)(user->http);
            NSDictionary* dic = nil;
            NSData* data = nil;
            for( int i=3 ; i<=argN ; i++ ) {
                int type = lv_type(L, i);
                if( type==LV_TSTRING ) {// 数据
                    NSString* s = lv_paramString(L, i);
                    data = [s dataUsingEncoding:NSUTF8StringEncoding];
                }
                if( type==LV_TTABLE ) {// 数据
                    NSDictionary* tempDic = lv_luaTableToDictionary(L, i);
                    NSString* s = [LVUtil objectToString:tempDic];
                    data = [s dataUsingEncoding:NSUTF8StringEncoding];
                }
                
                if( type==LV_TFUNCTION ) {
                    [LVUtil registryValue:L key:http.function stack:4];
                }
            }
            NSURL *url = [NSURL URLWithString:urlStr];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [request setHTTPMethod:@"POST"];
            [request setTimeoutInterval:http.timeout];
            
            // http头信息
            if( dic.count>0 ){
                for (NSString *key in dic) {
                    NSString* value = dic[key];
                    [request setValue:value forHTTPHeaderField:key];
                }
            }
            
            // data
            if( data.length>0 ){
                [request setHTTPBody:data];
            }
            
            NSOperationQueue *queue = [[NSOperationQueue alloc]init];
            http.connection = [[NSURLConnection alloc] initWithRequest:request delegate:http];
            [http.connection setDelegateQueue:queue];
            [http.connection start];
        }
    }
    return 0; /* new userdatum is already on the stack */
}

static int __gc (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    releaseUserDataHttp(user);
    return 0;
}

static int __tostring (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    if( user && LVIsType(user, LVUserDataHttp) ){
        LVHttp* http =  (__bridge LVHttp *)(user->http);
        NSString* s = [NSString stringWithFormat:@"LVUserDataHttp: %@\n response.data.length=%ld\n error:%@",
                       http.response.response,
                       (long)http.response.data.length,
                       http.response.error ];
        lv_pushstring(L, s.UTF8String);
        return 1;
    }
    return 0;
}

static int data (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    if( user && LVIsType(user, LVUserDataHttp) ){
        LVHttp* http =  (__bridge LVHttp *)(user->http);
        //        NSString* s = [NSString stringWithFormat:@"LVUserDataHttp: %@\n response.data.length=%ld\n error:%@",
        //                       http.response.response,
        //                       http.response.data.length,
        //                       http.response.error ];
        return [LVData createDataObject:L data:http.response.data];
    }
    return 0;
}
static int responseStatusCode (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    if( user && LVIsType(user, LVUserDataHttp) ){
        LVHttp* http =  (__bridge LVHttp *)(user->http);
        NSHTTPURLResponse* httpResponse = http.response.httpResponse;
        lv_pushnumber(L, httpResponse.statusCode);
        return 1;
    }
    return 0;
}
static int responseHeaderFields (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    if( user && LVIsType(user, LVUserDataHttp) ){
        LVHttp* http =  (__bridge LVHttp *)(user->http);
        NSHTTPURLResponse* response = http.response.httpResponse;
        lv_pushNativeObject(L,response.allHeaderFields);
        return 1;
    }
    return 0;
}
static int cancel (lv_State *L) {
    LVUserDataHttp * user = (LVUserDataHttp *)lv_touserdata(L, 1);
    if( user && LVIsType(user, LVUserDataHttp) ){
        LVHttp* http =  (__bridge LVHttp *)(user->http);
        [http.connection cancel];
        return 0;
    }
    return 0;
}

+(int) classDefine:(lv_State *)L {
    {
        const struct lvL_reg memberFunctions [] = {
            {"__gc", __gc },
            
            {"__tostring", __tostring },
            
            {"data", data },
            {"code", responseStatusCode },
            {"header", responseHeaderFields },
            
            {"get", get },
            {"post", post },
            
            {"cancel", cancel },
            
            {NULL, NULL}
        };
        
        lv_createClassMetaTable(L, META_TABLE_Http);
        
        lvL_openlib(L, NULL, memberFunctions, 0);
    }
    {
        lv_pushcfunction(L, lvNewHttpObject );
        lv_setglobal(L, "Http");
    }
    return 1;
}

@end
