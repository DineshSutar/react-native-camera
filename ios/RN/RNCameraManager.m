#import "RNCamera.h"
#import "RNCameraManager.h"
#import "RNFileSystem.h"
#import "RNImageUtils.h"
#import <React/RCTBridge.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/UIView+React.h>

@implementation RNCameraManager

RCT_EXPORT_MODULE(RNCameraManager);
RCT_EXPORT_VIEW_PROPERTY(onCameraReady, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onMountError, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onPictureTaken, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onPictureSaved, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onSubjectAreaChanged, RCTDirectEventBlock);

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

- (UIView *)view
{
    return [[RNCamera alloc] initWithBridge:self.bridge];
}

- (NSDictionary *)constantsToExport
{
    return @{
             @"Type" :
                 @{@"front" : @(RNCameraTypeFront), @"back" : @(RNCameraTypeBack)},
             @"FlashMode" : @{
                     @"off" : @(RNCameraFlashModeOff),
                     @"on" : @(RNCameraFlashModeOn),
                     @"auto" : @(RNCameraFlashModeAuto),
                     @"torch" : @(RNCameraFlashModeTorch)
                     },
             @"AutoFocus" :
                 @{@"on" : @(RNCameraAutoFocusOn), @"off" : @(RNCameraAutoFocusOff)},
             @"WhiteBalance" : @{
                     @"auto" : @(RNCameraWhiteBalanceAuto),
                     @"sunny" : @(RNCameraWhiteBalanceSunny),
                     @"cloudy" : @(RNCameraWhiteBalanceCloudy),
                     @"shadow" : @(RNCameraWhiteBalanceShadow),
                     @"incandescent" : @(RNCameraWhiteBalanceIncandescent),
                     @"fluorescent" : @(RNCameraWhiteBalanceFluorescent)
                     },
             @"Orientation": @{
                     @"auto": @(RNCameraOrientationAuto),
                     @"landscapeLeft": @(RNCameraOrientationLandscapeLeft),
                     @"landscapeRight": @(RNCameraOrientationLandscapeRight),
                     @"portrait": @(RNCameraOrientationPortrait),
                     @"portraitUpsideDown": @(RNCameraOrientationPortraitUpsideDown)
                     }
             };
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"onCameraReady", @"onMountError", @"onPictureTaken", @"onPictureSaved", @"onSubjectAreaChanged"];
}

+ (NSDictionary *)pictureSizes
{
    return @{
             @"3840x2160" : AVCaptureSessionPreset3840x2160,
             @"1920x1080" : AVCaptureSessionPreset1920x1080,
             @"1280x720" : AVCaptureSessionPreset1280x720,
             @"640x480" : AVCaptureSessionPreset640x480,
             @"352x288" : AVCaptureSessionPreset352x288,
             @"Photo" : AVCaptureSessionPresetPhoto,
             @"High" : AVCaptureSessionPresetHigh,
             @"Medium" : AVCaptureSessionPresetMedium,
             @"Low" : AVCaptureSessionPresetLow,
             @"None": @(-1),
             };
}

RCT_CUSTOM_VIEW_PROPERTY(type, NSInteger, RNCamera)
{
    NSInteger newType = [RCTConvert NSInteger:json];
    if (view.presetCamera != newType) {
        [view setPresetCamera:newType];
        [view updateType];
    }
}

RCT_CUSTOM_VIEW_PROPERTY(cameraId, NSString, RNCamera)
{
    NSString *newId = [RCTConvert NSString:json];

    // also compare pointers so we check for nulls
    if (view.cameraId != newId && ![view.cameraId isEqualToString:newId]) {
        [view setCameraId:newId];
        // using same call as setting the type here since they
        // both require the same updates
        [view updateType];
    }
}

RCT_CUSTOM_VIEW_PROPERTY(flashMode, NSInteger, RNCamera)
{
    [view setFlashMode:[RCTConvert NSInteger:json]];
    [view updateFlashMode];
}

RCT_CUSTOM_VIEW_PROPERTY(autoFocus, NSInteger, RNCamera)
{
    [view setAutoFocus:[RCTConvert NSInteger:json]];
    [view updateFocusMode];
}

RCT_CUSTOM_VIEW_PROPERTY(autoFocusPointOfInterest, NSDictionary, RNCamera)
{
    [view setAutoFocusPointOfInterest:[RCTConvert NSDictionary:json]];
    [view updateAutoFocusPointOfInterest];
}

RCT_CUSTOM_VIEW_PROPERTY(focusDepth, NSNumber, RNCamera)
{
    [view setFocusDepth:[RCTConvert float:json]];
    [view updateFocusDepth];
}

RCT_CUSTOM_VIEW_PROPERTY(zoom, NSNumber, RNCamera)
{
    [view setZoom:[RCTConvert CGFloat:json]];
    [view updateZoom];
}

RCT_CUSTOM_VIEW_PROPERTY(maxZoom, NSNumber, RNCamera)
{
    [view setMaxZoom:[RCTConvert CGFloat:json]];
    [view updateZoom];
}

RCT_CUSTOM_VIEW_PROPERTY(whiteBalance, NSInteger, RNCamera)
{
    [view setWhiteBalance:[RCTConvert NSInteger:json]];
    [view updateWhiteBalance];
}

RCT_CUSTOM_VIEW_PROPERTY(exposure, NSNumber, RNCamera)
{
    [view setExposure:[RCTConvert float:json]];
    [view updateExposure];
}

RCT_CUSTOM_VIEW_PROPERTY(pictureSize, NSString *, RNCamera)
{
    [view setPictureSize:[[self class] pictureSizes][[RCTConvert NSString:json]]];
    [view updatePictureSize];
}

RCT_REMAP_METHOD(takePicture,
                 options:(NSDictionary *)options
                 reactTag:(nonnull NSNumber *)reactTag
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCamera *> *viewRegistry) {
        RNCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNCamera, got: %@", view);
        } else {
#if TARGET_IPHONE_SIMULATOR
            NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
            float quality = [options[@"quality"] floatValue];
            NSString *path = [RNFileSystem generatePathInDirectory:[[RNFileSystem cacheDirectoryPath] stringByAppendingPathComponent:@"Camera"] withExtension:@".jpg"];
            UIImage *generatedPhoto = [RNImageUtils generatePhotoOfSize:CGSizeMake(200, 200)];
            BOOL useFastMode = options[@"fastMode"] && [options[@"fastMode"] boolValue];
            if (useFastMode) {
                resolve(nil);
            }

            [view onPictureTaken:@{}];

            NSData *photoData = UIImageJPEGRepresentation(generatedPhoto, quality);
            if (![options[@"doNotSave"] boolValue]) {
                response[@"uri"] = [RNImageUtils writeImage:photoData toPath:path];
            }
            response[@"width"] = @(generatedPhoto.size.width);
            response[@"height"] = @(generatedPhoto.size.height);
            if ([options[@"base64"] boolValue]) {
                response[@"base64"] = [photoData base64EncodedStringWithOptions:0];
            }
            if (useFastMode) {
                [view onPictureSaved:@{@"data": response, @"id": options[@"id"]}];
            } else {
                resolve(response);
            }
#else
            [view takePicture:options resolve:resolve reject:reject];
#endif
        }
    }];
}

RCT_EXPORT_METHOD(resumePreview:(nonnull NSNumber *)reactTag)
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCamera *> *viewRegistry) {
        RNCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNCamera, got: %@", view);
        } else {
            [view resumePreview];
        }
    }];
}

RCT_EXPORT_METHOD(pausePreview:(nonnull NSNumber *)reactTag)
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCamera *> *viewRegistry) {
        RNCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNCamera, got: %@", view);
        } else {
            [view pausePreview];
        }
    }];
}

RCT_EXPORT_METHOD(checkDeviceAuthorizationStatus:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject) {
    __block NSString *mediaType = AVMediaTypeVideo;

    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (!granted) {
            resolve(@(granted));
        }
        else {
            mediaType = AVMediaTypeAudio;
            [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
                resolve(@(granted));
            }];
        }
    }];
}

RCT_EXPORT_METHOD(checkVideoAuthorizationStatus:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject) {
#ifdef DEBUG
    if ([[NSBundle mainBundle].infoDictionary objectForKey:@"NSCameraUsageDescription"] == nil) {
        RCTLogWarn(@"Checking video permissions without having key 'NSCameraUsageDescription' defined in your Info.plist. If you do not add it your app will crash when being built in release mode. You will have to add it to your Info.plist file, otherwise RNCamera is not allowed to use the camera.  You can learn more about adding permissions here: https://stackoverflow.com/a/38498347/4202031");
        resolve(@(NO));
        return;
    }
#endif
    __block NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        resolve(@(granted));
    }];
}

RCT_REMAP_METHOD(getAvailablePictureSizes,
                 ratio:(NSString *)ratio
                 reactTag:(nonnull NSNumber *)reactTag
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve([[[self class] pictureSizes] allKeys]);
}

RCT_EXPORT_METHOD(getCameraIds:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {

#if TARGET_IPHONE_SIMULATOR
    resolve(@[]);
    return;
#endif

    NSMutableArray *res = [NSMutableArray array];


    // need to filter/search devices based on iOS version
    // these warnings can be easily seen on XCode
    if (@available(iOS 10.0, *)) {
        NSArray *captureDeviceType;


        if (@available(iOS 13.0, *)) {
            captureDeviceType = @[
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
                AVCaptureDeviceTypeBuiltInTelephotoCamera
                #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
                    ,AVCaptureDeviceTypeBuiltInUltraWideCamera
                #endif
            ];
        }
        else{
            captureDeviceType = @[
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
                AVCaptureDeviceTypeBuiltInTelephotoCamera
            ];
        }


        AVCaptureDeviceDiscoverySession *captureDevice =
        [AVCaptureDeviceDiscoverySession
         discoverySessionWithDeviceTypes:captureDeviceType
         mediaType:AVMediaTypeVideo
         position:AVCaptureDevicePositionUnspecified];

        for(AVCaptureDevice *camera in [captureDevice devices]){

            // exclude virtual devices. We currently cannot use
            // any virtual device feature like auto switching or
            // depth of field detetion anyways.
            #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
                if (@available(iOS 13.0, *)) {
                    if([camera isVirtualDevice]){
                        continue;
                    }
                }
            #endif


            if([camera position] == AVCaptureDevicePositionFront) {
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeFront),
                    @"deviceType": [camera deviceType]
                }];
            }
            else if([camera position] == AVCaptureDevicePositionBack){
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeBack),
                    @"deviceType": [camera deviceType]
                }];
            }

        }

    } else {
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for(AVCaptureDevice *camera in devices) {


            if([camera position] == AVCaptureDevicePositionFront) {
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeFront),
                    @"deviceType": @""
                }];
            }
            else if([camera position] == AVCaptureDevicePositionBack){
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeBack),
                    @"deviceType": @""
                }];
            }

        }
    }

    resolve(res);
}

@end
