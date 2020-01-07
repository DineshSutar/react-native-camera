#import "RNCamera.h"
#import "RNCameraUtils.h"
#import "RNImageUtils.h"
#import "RNFileSystem.h"
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/UIView+React.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import  "RNSensorOrientationChecker.h"
@interface RNCamera ()

@property (nonatomic, weak) RCTBridge *bridge;
@property (nonatomic,strong) RNSensorOrientationChecker * sensorOrientationChecker;

@property (nonatomic, copy) RCTDirectEventBlock onCameraReady;
@property (nonatomic, copy) RCTDirectEventBlock onMountError;
@property (nonatomic, copy) RCTDirectEventBlock onPictureTaken;
@property (nonatomic, copy) RCTDirectEventBlock onPictureSaved;

@property (nonatomic, copy) RCTDirectEventBlock onSubjectAreaChanged;
@property (nonatomic, assign) BOOL isFocusedOnPoint;
@property (nonatomic, assign) BOOL isExposedOnPoint;

@end

@implementation RNCamera

static NSDictionary *defaultFaceDetectorOptions = nil;

BOOL _recordRequested = NO;
BOOL _sessionInterrupted = NO;


- (id)initWithBridge:(RCTBridge *)bridge
{
    if ((self = [super init])) {
        self.bridge = bridge;
        self.session = [AVCaptureSession new];
        self.sessionQueue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_SERIAL);
        self.sensorOrientationChecker = [RNSensorOrientationChecker new];
#if !(TARGET_IPHONE_SIMULATOR)
        self.previewLayer =
        [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        self.previewLayer.needsDisplayOnBoundsChange = YES;
#endif
        self.rectOfInterest = CGRectMake(0, 0, 1.0, 1.0);
        self.autoFocus = -1;
        self.exposure = -1;
        self.presetCamera = AVCaptureDevicePositionUnspecified;
        self.cameraId = nil;
        self.isFocusedOnPoint = NO;
        self.isExposedOnPoint = NO;
        _recordRequested = NO;
        _sessionInterrupted = NO;
        self.filteredImageView = [UIImageView new];
        self.filteredImageView.transform = CGAffineTransformMakeRotation(M_PI_2);
        self.grayImageFilter = [CIFilter filterWithName:@"CIPhotoEffectMono"]; // CIPhotoEffectNoir
        
        // we will do other initialization after
        // the view is loaded.
        // This is to prevent code if the view is unused as react
        // might create multiple instances of it.
        // and we need to also add/remove event listeners.


    }
    return self;
}

- (void)onReady:(NSDictionary *)event
{
    if (_onCameraReady) {
        _onCameraReady(nil);
    }
}

- (void)onMountingError:(NSDictionary *)event
{
    if (_onMountError) {
        _onMountError(event);
    }
}

- (void)onPictureTaken:(NSDictionary *)event
{
    if (_onPictureTaken) {
        _onPictureTaken(event);
    }
}

- (void)onPictureSaved:(NSDictionary *)event
{
    if (_onPictureSaved) {
        _onPictureSaved(event);
    }
}

- (void)onSubjectAreaChanged:(NSDictionary *)event
{
    if (_onSubjectAreaChanged) {
        _onSubjectAreaChanged(event);
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.previewLayer.frame = self.bounds;
    self.filteredImageView.frame = self.bounds;
    
    [self setBackgroundColor:[UIColor blackColor]];
//    [self.layer insertSublayer:self.previewLayer atIndex:0];
    [self addSubview:self.filteredImageView];
}

- (void)insertReactSubview:(UIView *)view atIndex:(NSInteger)atIndex
{
    [self insertSubview:view atIndex:atIndex + 1]; // is this + 1 really necessary?
    [super insertReactSubview:view atIndex:atIndex];
    return;
}

- (void)removeReactSubview:(UIView *)subview
{
    [subview removeFromSuperview];
    [super removeReactSubview:subview];
    return;
}


- (void)willMoveToSuperview:(nullable UIView *)newSuperview;
{
    if(newSuperview != nil){

        [[NSNotificationCenter defaultCenter] addObserver:self
         selector:@selector(orientationChanged:)
             name:UIApplicationDidChangeStatusBarOrientationNotification
           object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionDidStartRunning:) name:AVCaptureSessionDidStartRunningNotification object:self.session];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];


        // this is not needed since RN will update our type value
        // after mount to set the camera's default, and that will already
        // this method
        // [self initializeCaptureSessionInput];
        [self startSession];
    }
    else{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionWasInterruptedNotification object:self.session];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionDidStartRunningNotification object:self.session];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionRuntimeErrorNotification object:self.session];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];

        [self stopSession];
    }

    [super willMoveToSuperview:newSuperview];
}



// Helper to get a device from the currently set properties (type and camera id)
// might return nil if device failed to be retrieved or is invalid
-(AVCaptureDevice*)getDevice
{
    AVCaptureDevice *captureDevice;
    if(self.cameraId != nil){
        captureDevice = [RNCameraUtils deviceWithCameraId:self.cameraId];
    }
    else{
        captureDevice = [RNCameraUtils deviceWithMediaType:AVMediaTypeVideo preferringPosition:self.presetCamera];
    }
    return captureDevice;

}

// helper to return the camera's instance default preset
// this is for pictures only, and video should set another preset
// before recording.
// This default preset returns much smoother photos than High.
-(AVCaptureSessionPreset)getDefaultPreset
{
    AVCaptureSessionPreset preset =
    ([self pictureSize] && [[self pictureSize] integerValue] >= 0) ? [self pictureSize] : AVCaptureSessionPresetPhoto;

    return preset;
}

-(void)updateType
{
    [self initializeCaptureSessionInput];
    [self startSession]; // will already check if session is running
}


- (void)updateFlashMode
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (self.flashMode == RNCameraFlashModeTorch) {
        if (![device hasTorch])
            return;
        if (![device lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }
        if (device.hasTorch && [device isTorchModeSupported:AVCaptureTorchModeOn])
        {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                [device setFlashMode:AVCaptureFlashModeOff];
                [device setTorchMode:AVCaptureTorchModeOn];
                [device unlockForConfiguration];
            } else {
                if (error) {
                    RCTLogError(@"%s: %@", __func__, error);
                }
            }
        }
    } else {
        if (![device hasFlash])
            return;
        if (![device lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }
        if (device.hasFlash && [device isFlashModeSupported:self.flashMode])
        {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                if ([device isTorchActive]) {
                    [device setTorchMode:AVCaptureTorchModeOff];
                }
                [device setFlashMode:self.flashMode];
                [device unlockForConfiguration];
            } else {
                if (error) {
                    RCTLogError(@"%s: %@", __func__, error);
                }
            }
        }
    }

    [device unlockForConfiguration];
}

// Function to cleanup focus listeners and variables on device
// change. This is required since "defocusing" might not be
// possible on the new device, and our device reference will be
// different
- (void)cleanupFocus:(AVCaptureDevice*) previousDevice {

    self.isFocusedOnPoint = NO;
    self.isExposedOnPoint = NO;

    // cleanup listeners if we had any
    if(previousDevice != nil){

        // remove event listener
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:previousDevice];

        // cleanup device flags
        NSError *error = nil;
        if (![previousDevice lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }

        previousDevice.subjectAreaChangeMonitoringEnabled = NO;

        [previousDevice unlockForConfiguration];

    }
}

- (void)defocusPointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];


    if (self.isFocusedOnPoint) {

        self.isFocusedOnPoint = NO;

        if(device == nil){
            return;
        }

        device.subjectAreaChangeMonitoringEnabled = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];

        CGPoint prevPoint = [device focusPointOfInterest];

        CGPoint autofocusPoint = CGPointMake(0.5f, 0.5f);

        [device setFocusPointOfInterest: autofocusPoint];

        [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];

        [self onSubjectAreaChanged:@{
            @"prevPointOfInterest": @{
                @"x": @(prevPoint.x),
                @"y": @(prevPoint.y)
            }
        }];
    }

    if(self.isExposedOnPoint){
        self.isExposedOnPoint = NO;

        if(device == nil){
            return;
        }

        CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);

        [device setExposurePointOfInterest: exposurePoint];

        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
}

- (void)deexposePointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];


    if(self.isExposedOnPoint){
        self.isExposedOnPoint = NO;

        if(device == nil){
            return;
        }

        CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);

        [device setExposurePointOfInterest: exposurePoint];

        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
}


- (void)updateAutoFocusPointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if ([self.autoFocusPointOfInterest objectForKey:@"x"] && [self.autoFocusPointOfInterest objectForKey:@"y"]) {

        float xValue = [self.autoFocusPointOfInterest[@"x"] floatValue];
        float yValue = [self.autoFocusPointOfInterest[@"y"] floatValue];

        CGPoint autofocusPoint = CGPointMake(xValue, yValue);


        if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {

            [device setFocusPointOfInterest:autofocusPoint];
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];

            if (!self.isFocusedOnPoint) {
                self.isFocusedOnPoint = YES;

                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(AutofocusDelegate:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];
                device.subjectAreaChangeMonitoringEnabled = YES;
            }
        } else {
            RCTLogWarn(@"AutoFocusPointOfInterest not supported");
        }

        if([self.autoFocusPointOfInterest objectForKey:@"autoExposure"]){
            BOOL autoExposure = [self.autoFocusPointOfInterest[@"autoExposure"] boolValue];

            if(autoExposure){
                if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
                {
                    [device setExposurePointOfInterest:autofocusPoint];
                    [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                    self.isExposedOnPoint = YES;

                } else {
                    RCTLogWarn(@"AutoExposurePointOfInterest not supported");
                }
            }
            else{
                [self deexposePointOfInterest];
            }
        }
        else{
            [self deexposePointOfInterest];
        }

    } else {
        [self defocusPointOfInterest];
        [self deexposePointOfInterest];
    }

    [device unlockForConfiguration];
}

-(void) AutofocusDelegate:(NSNotification*) notification {
    AVCaptureDevice* device = [notification object];

    if ([device lockForConfiguration:NULL] == YES ) {
        [self defocusPointOfInterest];
        [self deexposePointOfInterest];
        [device unlockForConfiguration];
    }
}

- (void)updateFocusMode
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if ([device isFocusModeSupported:self.autoFocus]) {
        if ([device lockForConfiguration:&error]) {
            [device setFocusMode:self.autoFocus];
        } else {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
        }
    }

    [device unlockForConfiguration];
}

- (void)updateFocusDepth
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if (device == nil || self.autoFocus < 0 || device.focusMode != RNCameraAutoFocusOff || device.position == RNCameraTypeFront) {
        return;
    }

    if (![device respondsToSelector:@selector(isLockingFocusWithCustomLensPositionSupported)] || ![device isLockingFocusWithCustomLensPositionSupported]) {
        RCTLogWarn(@"%s: Setting focusDepth isn't supported for this camera device", __func__);
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    __weak __typeof__(device) weakDevice = device;
    [device setFocusModeLockedWithLensPosition:self.focusDepth completionHandler:^(CMTime syncTime) {
        [weakDevice unlockForConfiguration];
    }];
}

- (void)updateZoom {
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    float maxZoom;
    if(self.maxZoom > 1){
        maxZoom = MIN(self.maxZoom, device.activeFormat.videoMaxZoomFactor);
    }
    else{
        maxZoom = device.activeFormat.videoMaxZoomFactor;
    }

    device.videoZoomFactor = (maxZoom - 1) * self.zoom + 1;


    [device unlockForConfiguration];
}

- (void)updateWhiteBalance
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if (self.whiteBalance == RNCameraWhiteBalanceAuto) {
        [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        [device unlockForConfiguration];
    } else {
        AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
            .temperature = [RNCameraUtils temperatureForWhiteBalance:self.whiteBalance],
            .tint = 0,
        };
        AVCaptureWhiteBalanceGains rgbGains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint];
        __weak __typeof__(device) weakDevice = device;
        if ([device lockForConfiguration:&error]) {
            @try{
                [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:rgbGains completionHandler:^(CMTime syncTime) {
                    [weakDevice unlockForConfiguration];
                }];
            }
            @catch(NSException *exception){
                RCTLogError(@"Failed to set white balance: %@", exception);
            }
        } else {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
        }
    }

    [device unlockForConfiguration];
}


/// Set the AVCaptureDevice's ISO values based on RNCamera's 'exposure' value,
/// which is a float between 0 and 1 if defined by the user or -1 to indicate that no
/// selection is active. 'exposure' gets mapped to a valid ISO value between the
/// device's min/max-range of ISO-values.
///
/// The exposure gets reset every time the user manually sets the autofocus-point in
/// 'updateAutoFocusPointOfInterest' automatically. Currently no explicit event is fired.
/// This leads to two 'exposure'-states: one here and one in the component, which is
/// fine. 'exposure' here gets only synced if 'exposure' on the js-side changes. You
/// can manually keep the state in sync by setting 'exposure' in your React-state
/// everytime the js-updateAutoFocusPointOfInterest-function gets called.
- (void)updateExposure
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    // Check that either no explicit exposure-val has been set yet
    // or that it has been reset. Check for > 1 is only a guard.
    if(self.exposure < 0 || self.exposure > 1){
        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [device unlockForConfiguration];
        return;
    }

    // Lazy init of range.
    if(!self.exposureIsoMin){ self.exposureIsoMin = device.activeFormat.minISO; }
    if(!self.exposureIsoMax){ self.exposureIsoMax = device.activeFormat.maxISO; }

    // Get a valid ISO-value in range from min to max. After we mapped the exposure
    // (a val between 0 - 1), the result gets corrected by the offset from 0, which
    // is the min-ISO-value.
    float appliedExposure = (self.exposureIsoMax - self.exposureIsoMin) * self.exposure + self.exposureIsoMin;

    // Make sure we're in AVCaptureExposureModeCustom, else the ISO + duration time won't apply.
    // Also make sure the device can set exposure
    if([device isExposureModeSupported:AVCaptureExposureModeCustom]){
        if(device.exposureMode != AVCaptureExposureModeCustom){
            [device setExposureMode:AVCaptureExposureModeCustom];
        }

        // Only set the ISO for now, duration will be default as a change might affect frame rate.
        [device setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:appliedExposure completionHandler:nil];
    }
    else{
        RCTLog(@"Device does not support AVCaptureExposureModeCustom");
    }
    [device unlockForConfiguration];
}

- (void)updatePictureSize
{
    // make sure to call this function so the right default is used if
    // "None" is used
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}

- (void)takePictureWithOrientation:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject{
    [self.sensorOrientationChecker getDeviceOrientationWithBlock:^(UIInterfaceOrientation orientation) {
        NSMutableDictionary *tmpOptions = [options mutableCopy];
        if ([tmpOptions valueForKey:@"orientation"] == nil) {
            tmpOptions[@"orientation"] = [NSNumber numberWithInteger:[self.sensorOrientationChecker convertToAVCaptureVideoOrientation:orientation]];
        }
        self.deviceOrientation = [NSNumber numberWithInteger:orientation];
        self.orientation = [NSNumber numberWithInteger:[tmpOptions[@"orientation"] integerValue]];
        [self takePicture:tmpOptions resolve:resolve reject:reject];
    }];
}

- (void)takePicture:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
    // if video device is not set, reject
    if(self.videoCaptureDeviceInput == nil || !self.session.isRunning){
        reject(@"E_IMAGE_CAPTURE_FAILED", @"Camera is not ready.", nil);
        return;
    }

    if (!self.deviceOrientation) {
        [self takePictureWithOrientation:options resolve:resolve reject:reject];
        return;
    }

    NSInteger orientation = [options[@"orientation"] integerValue];

    AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:orientation];
    @try {
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
            if (imageSampleBuffer && !error) {

                if ([options[@"pauseAfterCapture"] boolValue]) {
                    [[self.previewLayer connection] setEnabled:NO];
                }

                BOOL useFastMode = [options valueForKey:@"fastMode"] != nil && [options[@"fastMode"] boolValue];
                if (useFastMode) {
                    resolve(nil);
                }

                [self onPictureTaken:@{}];


                // get JPEG image data
//                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
//                UIImage *takenImage = [UIImage imageWithData:imageData];
                UIImage *takenImage = self.filteredImageView.image;
                CGSize takenImgSize = takenImage.size;
                CGRect cropRect = CGRectMake(0, 0, takenImgSize.width, takenImgSize.height);
                
                CIContext *context = [CIContext new];
                takenImage = [UIImage imageWithCGImage:[context createCGImage:takenImage.CIImage fromRect:cropRect]];

                // Adjust/crop image based on preview dimensions
                // TODO: This seems needed because iOS does not allow
                // for aspect ratio settings, so this is the best we can get
                // to mimic android's behaviour.
                CGSize previewSize;
                if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
                    previewSize = CGSizeMake(self.filteredImageView.frame.size.height, self.filteredImageView.frame.size.width);
                } else {
                    previewSize = CGSizeMake(self.filteredImageView.frame.size.width, self.filteredImageView.frame.size.height);
                }
                
                CGRect croppedSize = AVMakeRectWithAspectRatioInsideRect(previewSize, cropRect);
                takenImage = [RNImageUtils cropImage:takenImage toRect:croppedSize];

                // apply other image settings
                bool resetOrientation = NO;
                if ([options[@"mirrorImage"] boolValue]) {
                    takenImage = [RNImageUtils mirrorImage:takenImage];
                }
                if ([options[@"forceUpOrientation"] boolValue]) {
                    takenImage = [RNImageUtils forceUpOrientation:takenImage];
                    resetOrientation = YES;
                }
                if ([options[@"width"] integerValue]) {
                    takenImage = [RNImageUtils scaleImage:takenImage toWidth:[options[@"width"] integerValue]];
                    resetOrientation = YES;
                }

                // get image metadata so we can re-add it later
                // make it mutable since we need to adjust quality/compression
                CFDictionaryRef metaDict = CMCopyDictionaryOfAttachments(NULL, imageSampleBuffer, kCMAttachmentMode_ShouldPropagate);

                CFMutableDictionaryRef mutableMetaDict = CFDictionaryCreateMutableCopy(NULL, 0, metaDict);

                // release the meta dict now that we've copied it
                // to Objective-C land
                CFRelease(metaDict);

                // bridge the copy for auto release
                NSMutableDictionary *metadata = (NSMutableDictionary *)CFBridgingRelease(mutableMetaDict);


                // Get final JPEG image and set compression
                float quality = [options[@"quality"] floatValue];
                [metadata setObject:@(quality) forKey:(__bridge NSString *)kCGImageDestinationLossyCompressionQuality];

                // Reset exif orientation if we need to due to image changes
                // that already rotate the image.
                // Other dimension attributes will be set automatically
                // regardless of what we have on our metadata dict
                if (resetOrientation){
                    metadata[(NSString*)kCGImagePropertyOrientation] = @(1);
                }


                // get our final image data with added metadata
                // idea taken from: https://stackoverflow.com/questions/9006759/how-to-write-exif-metadata-to-an-image-not-the-camera-roll-just-a-uiimage-or-j/9091472
                NSMutableData * destData = [NSMutableData data];

                CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)destData, kUTTypeJPEG, 1, NULL);

                // defaults to true, must like Android
                bool writeExif = true;

                if(options[@"writeExif"]){

                    // if we received an object, merge with our meta
                    if ([options[@"writeExif"] isKindOfClass:[NSDictionary class]]){
                        NSDictionary *newExif = options[@"writeExif"];

                        // need to update both, since apple splits data
                        // across exif and tiff dicts. No problems with duplicates
                        // they will be handled appropiately.
                        NSMutableDictionary *exif = metadata[(NSString*)kCGImagePropertyExifDictionary];

                        NSMutableDictionary *tiff = metadata[(NSString*)kCGImagePropertyTIFFDictionary];


                        // initialize exif dict if not built
                        if(!exif){
                            exif = [[NSMutableDictionary alloc] init];
                            metadata[(NSString*)kCGImagePropertyExifDictionary] = exif;
                        }

                        if(!tiff){
                            tiff = [[NSMutableDictionary alloc] init];
                            metadata[(NSString*)kCGImagePropertyTIFFDictionary] = exif;
                        }

                        // merge new exif info
                        [exif addEntriesFromDictionary:newExif];
                        [tiff addEntriesFromDictionary:newExif];


                        // correct any GPS metadata like Android does
                        // need to get the right format for each value.
                        NSMutableDictionary *gpsDict = [[NSMutableDictionary alloc] init];

                        if(newExif[@"GPSLatitude"]){
                            gpsDict[(NSString *)kCGImagePropertyGPSLatitude] = @(fabs([newExif[@"GPSLatitude"] floatValue]));

                            gpsDict[(NSString *)kCGImagePropertyGPSLatitudeRef] = [newExif[@"GPSLatitude"] floatValue] >= 0 ? @"N" : @"S";

                        }
                        if(newExif[@"GPSLongitude"]){
                            gpsDict[(NSString *)kCGImagePropertyGPSLongitude] = @(fabs([newExif[@"GPSLongitude"] floatValue]));

                            gpsDict[(NSString *)kCGImagePropertyGPSLongitudeRef] = [newExif[@"GPSLongitude"] floatValue] >= 0 ? @"E" : @"W";
                        }
                        if(newExif[@"GPSAltitude"]){
                            gpsDict[(NSString *)kCGImagePropertyGPSAltitude] = @(fabs([newExif[@"GPSAltitude"] floatValue]));

                            gpsDict[(NSString *)kCGImagePropertyGPSAltitudeRef] = [newExif[@"GPSAltitude"] floatValue] >= 0 ? @(0) : @(1);
                        }

                        // if we don't have gps info, add it
                        // otherwise, merge it
                        if(!metadata[(NSString *)kCGImagePropertyGPSDictionary]){
                            metadata[(NSString *)kCGImagePropertyGPSDictionary] = gpsDict;
                        }
                        else{
                            [metadata[(NSString *)kCGImagePropertyGPSDictionary] addEntriesFromDictionary:gpsDict];
                        }

                    }
                    else{
                        writeExif = [options[@"writeExif"] boolValue];
                    }

                }

                CGImageDestinationAddImage(destination, takenImage.CGImage, writeExif ? ((__bridge CFDictionaryRef) metadata) : nil);


                // write final image data with metadata to our destination
                if (CGImageDestinationFinalize(destination)){

                    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];

                    NSString *path = [RNFileSystem generatePathInDirectory:[[RNFileSystem cacheDirectoryPath] stringByAppendingPathComponent:@"Camera"] withExtension:@".jpg"];

                    if (![options[@"doNotSave"] boolValue]) {
                        response[@"uri"] = [RNImageUtils writeImage:destData toPath:path];
                    }
                    response[@"width"] = @(takenImage.size.width);
                    response[@"height"] = @(takenImage.size.height);

                    if ([options[@"base64"] boolValue]) {
                        response[@"base64"] = [destData base64EncodedStringWithOptions:0];
                    }

                    if ([options[@"exif"] boolValue]) {
                        response[@"exif"] = metadata;

                        // No longer needed since we always get the photo metadata now
                        //[RNImageUtils updatePhotoMetadata:imageSampleBuffer withAdditionalData:@{ @"Orientation": @(imageRotation) } inResponse:response]; // TODO
                    }

                    response[@"pictureOrientation"] = @([self.orientation integerValue]);
                    response[@"deviceOrientation"] = @([self.deviceOrientation integerValue]);
                    self.orientation = nil;
                    self.deviceOrientation = nil;

                    if (useFastMode) {
                        [self onPictureSaved:@{@"data": response, @"id": options[@"id"]}];
                    } else {
                        resolve(response);
                    }
                }
                else{
                    reject(@"E_IMAGE_CAPTURE_FAILED", @"Image could not be saved", error);
                }

                // release image resource
                @try{
                    CFRelease(destination);
                }
                @catch(NSException *exception){
                    RCTLogError(@"Failed to release CGImageDestinationRef: %@", exception);
                }

            } else {
                reject(@"E_IMAGE_CAPTURE_FAILED", @"Image could not be captured", error);
            }
        }];
    } @catch (NSException *exception) {
        reject(
               @"E_IMAGE_CAPTURE_FAILED",
               @"Got exception while taking picture",
               [NSError errorWithDomain:@"E_IMAGE_CAPTURE_FAILED" code: 500 userInfo:@{NSLocalizedDescriptionKey:exception.reason}]
        );
    }
}


- (void)resumePreview
{
    [[self.previewLayer connection] setEnabled:YES];
}

- (void)pausePreview
{
    [[self.previewLayer connection] setEnabled:NO];
}

- (void)startSession
{
#if TARGET_IPHONE_SIMULATOR
    [self onReady:nil];
    return;
#endif
    dispatch_async(self.sessionQueue, ^{

        // if session already running, also return and fire ready event
        // this is helpfu when the device type or ID is changed and we must
        // receive another ready event (like Android does)
        if(self.session.isRunning) {
            [self onReady:nil];
            return;
        }

        // if camera not set (invalid type and no ID) return.
        if (self.presetCamera == AVCaptureDevicePositionUnspecified && self.cameraId == nil) {
            return;
        }

        // video device was not initialized, also return
        if(self.videoCaptureDeviceInput == nil){
            return;
        }


        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ([self.session canAddOutput:stillImageOutput]) {
            stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
            [self.session addOutput:stillImageOutput];
            [stillImageOutput setHighResolutionStillImageOutputEnabled:YES];
            self.stillImageOutput = stillImageOutput;
        }

        [self setupGrayFilter];

        _sessionInterrupted = NO;
        [self.session startRunning];
        [self onReady:nil];
    });
}

- (void)stopSession
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    dispatch_async(self.sessionQueue, ^{
        [self.previewLayer removeFromSuperlayer];
        [self.session commitConfiguration];
        [self.session stopRunning];

        for (AVCaptureInput *input in self.session.inputs) {
            [self.session removeInput:input];
        }

        for (AVCaptureOutput *output in self.session.outputs) {
            [self.session removeOutput:output];
        }

        // clean these up as well since we've removed
        // all inputs and outputs from session
        self.videoCaptureDeviceInput = nil;
    });
}

- (void)initializeCaptureSessionInput
{

    dispatch_async(self.sessionQueue, ^{

        // Do all camera initialization in the session queue
        // to prevent it from
        AVCaptureDevice *captureDevice = [self getDevice];

        // if setting a new device is the same we currently have, nothing to do
        // return.
        if(self.videoCaptureDeviceInput != nil && captureDevice != nil && [self.videoCaptureDeviceInput.device.uniqueID isEqualToString:captureDevice.uniqueID]){
            return;
        }

        // if the device we are setting is also invalid/nil, return
        if(captureDevice == nil){
            [self onMountingError:@{@"message": @"Invalid camera device."}];
            return;
        }

        // get orientation also in our session queue to prevent
        // race conditions and also blocking the main thread
        __block UIInterfaceOrientation interfaceOrientation;

        dispatch_sync(dispatch_get_main_queue(), ^{
            interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
        });

        AVCaptureVideoOrientation orientation = [RNCameraUtils videoOrientationForInterfaceOrientation:interfaceOrientation];


        [self.session beginConfiguration];

        NSError *error = nil;
        AVCaptureDeviceInput *captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];

        if(error != nil){
            NSLog(@"Capture device error %@", error);
        }

        if (error || captureDeviceInput == nil) {
            RCTLog(@"%s: %@", __func__, error);
            [self.session commitConfiguration];
            [self onMountingError:@{@"message": @"Failed to setup capture device."}];
            return;
        }


        // Do additional cleanup that might be needed on the
        // previous device, if any.
        AVCaptureDevice *previousDevice = self.videoCaptureDeviceInput != nil ? self.videoCaptureDeviceInput.device : nil;

        [self cleanupFocus:previousDevice];


        // Remove inputs
        [self.session removeInput:self.videoCaptureDeviceInput];

        // clear this variable before setting it again.
        // Otherwise, if setting fails, we end up with a stale value.
        // and we are no longer able to detect if it changed or not
        self.videoCaptureDeviceInput = nil;

        // setup our capture preset based on what was set from RN
        // and our defaults
        // if the preset is not supported (e.g., when switching cameras)
        // canAddInput below will fail
        self.session.sessionPreset = [self getDefaultPreset];


        if ([self.session canAddInput:captureDeviceInput]) {
            [self.session addInput:captureDeviceInput];

            self.videoCaptureDeviceInput = captureDeviceInput;

            // Update all these async after our session has commited
            // since some values might be changed on session commit.
            dispatch_async(self.sessionQueue, ^{
                [self updateZoom];
                [self updateFocusMode];
                [self updateFocusDepth];
                [self updateExposure];
                [self updateAutoFocusPointOfInterest];
                [self updateWhiteBalance];
                [self updateFlashMode];
            });

            [self.previewLayer.connection setVideoOrientation:orientation];
        }
        else{
            RCTLog(@"The selected device does not work with the Preset [%@] or configuration provided", self.session.sessionPreset);
            
            [self onMountingError:@{@"message": @"Camera device does not support selected settings."}];
        }


        [self.session commitConfiguration];
    });
}

#pragma mark - internal

- (void)updateSessionPreset:(AVCaptureSessionPreset)preset
{
#if !(TARGET_IPHONE_SIMULATOR)
    if ([preset integerValue] < 0) {
        return;
    }
    if (preset) {
        dispatch_async(self.sessionQueue, ^{
            if ([self.session canSetSessionPreset:preset]) {
                [self.session beginConfiguration];
                self.session.sessionPreset = preset;
                [self.session commitConfiguration];

                // Need to update these since it gets reset on preset change
                [self updateFlashMode];
                [self updateZoom];
            }
            else{
                RCTLog(@"The selected preset [%@] does not work with the current session.", preset);
            }
        });
    }
#endif
}

// session interrupted events
- (void)sessionWasInterrupted:(NSNotification *)notification
{
    // Mark session interruption
    _sessionInterrupted = YES;

    // prevent any video recording start that we might have on the way
    _recordRequested = NO;
}


// update flash and our interrupted flag on session resume
- (void)sessionDidStartRunning:(NSNotification *)notification
{
    //NSLog(@"sessionDidStartRunning Was interrupted? %d", _sessionInterrupted);

    if(_sessionInterrupted){
        // resume flash value since it will be resetted / turned off
        dispatch_async(self.sessionQueue, ^{
            [self updateFlashMode];
        });
    }

    _sessionInterrupted = NO;
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    // Manually restarting the session since it must
    // have been stopped due to an error.
    dispatch_async(self.sessionQueue, ^{
         _sessionInterrupted = NO;
        [self.session startRunning];
        [self onReady:nil];
    });
}

- (void)orientationChanged:(NSNotification *)notification
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    [self changePreviewOrientation:orientation];
}

- (void)changePreviewOrientation:(UIInterfaceOrientation)orientation
{
    __weak typeof(self) weakSelf = self;
    AVCaptureVideoOrientation videoOrientation = [RNCameraUtils videoOrientationForInterfaceOrientation:orientation];
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.previewLayer.connection.isVideoOrientationSupported) {
            [strongSelf.previewLayer.connection setVideoOrientation:videoOrientation];
        }
    });
}

- (void)cleanupCamera {
    self.deviceOrientation = nil;
    self.orientation = nil;
    
    // reset preset to current default
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}

- (void)setupGrayFilter
{
    if (!self.videoDataOutput) {
        self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        if (![self.session canAddOutput:_videoDataOutput]) {
            NSLog(@"Failed to setup video data output");
            return;
        }
        
        [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
        [self.videoDataOutput setSampleBufferDelegate:self queue:self.sessionQueue];
        [self.session addOutput:_videoDataOutput];
    }
}

- (void)mirrorVideo:(NSURL *)inputURL completion:(void (^)(NSURL* outputUR))completion {
    AVAsset* videoAsset = [AVAsset assetWithURL:inputURL];
    AVAssetTrack* clipVideoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];

    AVMutableComposition* composition = [[AVMutableComposition alloc] init];
    [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];

    AVMutableVideoComposition* videoComposition = [[AVMutableVideoComposition alloc] init];
    videoComposition.renderSize = CGSizeMake(clipVideoTrack.naturalSize.height, clipVideoTrack.naturalSize.width);
    videoComposition.frameDuration = CMTimeMake(1, 30);

    AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:clipVideoTrack];

    AVMutableVideoCompositionInstruction* instruction = [[AVMutableVideoCompositionInstruction alloc] init];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, 30));

    CGAffineTransform transform = CGAffineTransformMakeScale(-1.0, 1.0);
    transform = CGAffineTransformTranslate(transform, -clipVideoTrack.naturalSize.width, 0);
    transform = CGAffineTransformRotate(transform, M_PI/2.0);
    transform = CGAffineTransformTranslate(transform, 0.0, -clipVideoTrack.naturalSize.width);

    [transformer setTransform:transform atTime:kCMTimeZero];

    [instruction setLayerInstructions:@[transformer]];
    [videoComposition setInstructions:@[instruction]];

    // Export
    AVAssetExportSession* exportSession = [AVAssetExportSession exportSessionWithAsset:videoAsset presetName:AVAssetExportPreset640x480];
    NSString* filePath = [RNFileSystem generatePathInDirectory:[[RNFileSystem cacheDirectoryPath] stringByAppendingString:@"CameraFlip"] withExtension:@".mp4"];
    NSURL* outputURL = [NSURL fileURLWithPath:filePath];
    [exportSession setOutputURL:outputURL];
    [exportSession setOutputFileType:AVFileTypeMPEG4];
    [exportSession setVideoComposition:videoComposition];
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(outputURL);
            });
        } else {
            NSLog(@"Export failed %@", exportSession.error);
        }
    }];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer options:nil];
    [self.grayImageFilter setValue:sourceImage forKey:kCIInputImageKey];
    CIImage *filteredImage = [self.grayImageFilter outputImage];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.filteredImageView.image = [UIImage imageWithCIImage:filteredImage];
    });
}

@end

