// Type definitions for react-native-camera 1.0
// Definitions by: Felipe Constantino <https://github.com/fconstant>
//                 Trent Jones <https://github.com/FizzBuzz791>
// If you modify this file, put your GitHub info here as well (for easy contacting purposes)

/*
 * Author notes:
 * I've tried to find a easy tool to convert from Flow to Typescript definition files (.d.ts).
 * So we woudn't have to do it manually... Sadly, I haven't found it.
 *
 * If you are seeing this from the future, please, send us your cutting-edge technology :) (if it exists)
 */
import { Component, ReactNode } from 'react';
import { NativeMethodsMixinStatic, ViewProperties, findNodeHandle } from 'react-native';

type Orientation = Readonly<{
  auto: any;
  landscapeLeft: any;
  landscapeRight: any;
  portrait: any;
  portraitUpsideDown: any;
}>;
type OrientationNumber = 1 | 2 | 3 | 4;
type AutoFocus = Readonly<{ on: any; off: any }>;
type FlashMode = Readonly<{ on: any; off: any; torch: any; auto: any }>;
type CameraType = Readonly<{ front: any; back: any }>;
type WhiteBalance = Readonly<{
  sunny: any;
  cloudy: any;
  shadow: any;
  incandescent: any;
  fluorescent: any;
  auto: any;
}>;

// FaCC (Function as Child Components)
type Self<T> = { [P in keyof T]: P };
type CameraStatus = Readonly<Self<{ READY: any; PENDING_AUTHORIZATION: any; NOT_AUTHORIZED: any }>>;
type FaCC = (params: { camera: RNCamera; status: keyof CameraStatus }) => JSX.Element;

export interface Constants {
  CameraStatus: CameraStatus;
  AutoFocus: AutoFocus;
  FlashMode: FlashMode;
  Type: CameraType;
  WhiteBalance: WhiteBalance;
  Orientation: {
    auto: 'auto';
    landscapeLeft: 'landscapeLeft';
    landscapeRight: 'landscapeRight';
    portrait: 'portrait';
    portraitUpsideDown: 'portraitUpsideDown';
  };
}

export interface RNCameraProps {
  children?: ReactNode | FaCC;

  autoFocus?: keyof AutoFocus;
  autoFocusPointOfInterest?: Point;
  /* iOS only */
  onSubjectAreaChanged?: (event: { nativeEvent: { prevPoint: { x: number; y: number } } }) => void;
  type?: keyof CameraType;
  flashMode?: keyof FlashMode;
  notAuthorizedView?: JSX.Element;
  pendingAuthorizationView?: JSX.Element;
  useCamera2Api?: boolean;
  exposure?: number;
  whiteBalance?: keyof WhiteBalance;

  onCameraReady?(): void;
  onStatusChange?(event: { cameraStatus: keyof CameraStatus }): void;
  onMountError?(error: { message: string }): void;

  /** Value: float from 0 to 1.0 */
  zoom?: number;
  /** iOS only. float from 0 to any. Locks the max zoom value to the provided value
    A value <= 1 will use the camera's max zoom, while a value > 1
    will use that value as the max available zoom
  **/
  maxZoom?: number;
  /** Value: float from 0 to 1.0 */
  focusDepth?: number;
  // -- ANDROID ONLY PROPS
  /** Android only */
  ratio?: string;
  /** Android only - Deprecated */
  permissionDialogTitle?: string;
  /** Android only - Deprecated */
  permissionDialogMessage?: string;
  /** Android only */
  playSoundOnCapture?: boolean;

  androidCameraPermissionOptions?: {
    title: string;
    message: string;
    buttonPositive?: string;
    buttonNegative?: string;
    buttonNeutral?: string;
  } | null;
}

interface Point<T = number> {
  x: T;
  y: T;
}

interface Size<T = number> {
  width: T;
  height: T;
}

interface TakePictureOptions {
  quality?: number;
  orientation?: keyof Orientation | OrientationNumber;
  base64?: boolean;
  exif?: boolean;
  width?: number;
  mirrorImage?: boolean;
  doNotSave?: boolean;
  pauseAfterCapture?: boolean;
  writeExif?: boolean | { [name: string]: any };

  /** Android only */
  fixOrientation?: boolean;

  /** iOS only */
  forceUpOrientation?: boolean;
}

export interface TakePictureResponse {
  width: number;
  height: number;
  uri: string;
  base64?: string;
  exif?: { [name: string]: any };
  pictureOrientation: number;
  deviceOrientation: number;
}

export class RNCamera extends Component<RNCameraProps & ViewProperties> {
  static Constants: Constants;

  _cameraRef: null | NativeMethodsMixinStatic;
  _cameraHandle: ReturnType<typeof findNodeHandle>;

  takePictureAsync(options?: TakePictureOptions): Promise<TakePictureResponse>;
  refreshAuthorizationStatus(): Promise<void>;
  pausePreview(): void;
  resumePreview(): void;
  getAvailablePictureSizes(): Promise<string[]>;

  /** Android only */
  getSupportedRatiosAsync(): Promise<string[]>;
}

// -- DEPRECATED CONTENT BELOW

/**
 * @deprecated As of 1.0.0 release, RCTCamera is deprecated. Please use RNCamera for the latest fixes and improvements.
 */
export default class RCTCamera extends Component<any> {
  static constants: any;
}
