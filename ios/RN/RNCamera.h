#import <AVFoundation/AVFoundation.h>
#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>
#import <UIKit/UIKit.h>

@class RNCamera;

@interface RNCamera : UIView <AVCaptureMetadataOutputObjectsDelegate,
                              AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, strong) CIFilter * _Nullable grayImageFilter;
@property(nonatomic, strong) UIImageView * _Nullable filteredImageView;
@property(nonatomic, strong) dispatch_queue_t _Nullable sessionQueue;
@property(nonatomic, strong) AVCaptureSession * _Nullable session;
@property(nonatomic, strong) AVCaptureDeviceInput * _Nullable videoCaptureDeviceInput;
@property(nonatomic, strong) AVCaptureStillImageOutput * _Nullable stillImageOutput;
@property(nonatomic, strong) AVCaptureVideoDataOutput * _Nullable videoDataOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer * _Nullable previewLayer;
@property(nonatomic, strong) id _Nonnull runtimeErrorHandlingObserver;

@property(nonatomic, assign) NSInteger presetCamera;
@property(nonatomic, copy) NSString * _Nullable cameraId; // copy required for strings/pointers
@property(assign, nonatomic) NSInteger flashMode;
@property(assign, nonatomic) CGFloat zoom;
@property(assign, nonatomic) CGFloat maxZoom;
@property(assign, nonatomic) NSInteger autoFocus;
@property(copy, nonatomic) NSDictionary * _Nullable autoFocusPointOfInterest;
@property(assign, nonatomic) float focusDepth;
@property(assign, nonatomic) NSInteger whiteBalance;
@property(assign, nonatomic) float exposure;
@property(assign, nonatomic) float exposureIsoMin;
@property(assign, nonatomic) float exposureIsoMax;
@property(assign, nonatomic) AVCaptureSessionPreset _Nullable pictureSize;
@property(nonatomic, assign) CGRect rectOfInterest;
@property(assign, nonatomic, nullable) NSNumber *deviceOrientation;
@property(assign, nonatomic, nullable) NSNumber *orientation;

- (id _Nonnull )initWithBridge:(RCTBridge *_Nullable)bridge;
- (void)updateType;
- (void)updateFlashMode;
- (void)updateFocusMode;
- (void)updateFocusDepth;
- (void)updateAutoFocusPointOfInterest;
- (void)updateZoom;
- (void)updateWhiteBalance;
- (void)updateExposure;
- (void)updatePictureSize;

- (void)takePicture:(NSDictionary *_Nullable)options
            resolve:(RCTPromiseResolveBlock _Nullable)resolve
             reject:(RCTPromiseRejectBlock _Nullable)reject;
- (void)takePictureWithOrientation:(NSDictionary *_Nullable)options
                           resolve:(RCTPromiseResolveBlock _Nullable)resolve
                            reject:(RCTPromiseRejectBlock _Nullable)reject;
- (void)resumePreview;
- (void)pausePreview;
- (void)onReady:(NSDictionary *_Nullable)event;
- (void)onMountingError:(NSDictionary *_Nullable)event;
- (void)onPictureTaken:(NSDictionary *_Nullable)event;
- (void)onPictureSaved:(NSDictionary *_Nullable)event;

- (void)onSubjectAreaChanged:(NSDictionary *_Nullable)event;

@end
