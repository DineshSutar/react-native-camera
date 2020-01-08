// @flow
import React from 'react';
import PropTypes from 'prop-types';
import {
  findNodeHandle,
  Platform,
  NativeModules,
  ViewPropTypes,
  requireNativeComponent,
  View,
  ActivityIndicator,
  Text,
  StyleSheet,
  PermissionsAndroid,
} from 'react-native';

const Rationale = PropTypes.shape({
  title: PropTypes.string.isRequired,
  message: PropTypes.string.isRequired,
  buttonPositive: PropTypes.string,
  buttonNegative: PropTypes.string,
  buttonNeutral: PropTypes.string,
});

const requestPermissions = async (
  CameraManager: any,
  androidCameraPermissionOptions: Rationale,
): Promise<{ hasCameraPermissions: boolean }> => {
  let hasCameraPermissions = false;

  if (Platform.OS === 'ios') {
    hasCameraPermissions = await CameraManager.checkVideoAuthorizationStatus();
  } else if (Platform.OS === 'android') {
    const cameraPermissionResult = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.CAMERA,
      androidCameraPermissionOptions,
    );
    if (typeof cameraPermissionResult === 'boolean') {
      hasCameraPermissions = cameraPermissionResult;
    } else {
      hasCameraPermissions = cameraPermissionResult === PermissionsAndroid.RESULTS.GRANTED;
    }
  }

  return {
    hasCameraPermissions,
  };
};

const styles = StyleSheet.create({
  authorizationContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notAuthorizedText: {
    textAlign: 'center',
    fontSize: 16,
  },
});

type Orientation = 'auto' | 'landscapeLeft' | 'landscapeRight' | 'portrait' | 'portraitUpsideDown';
type OrientationNumber = 1 | 2 | 3 | 4;

type PictureOptions = {
  quality?: number,
  orientation?: Orientation | OrientationNumber,
  base64?: boolean,
  mirrorImage?: boolean,
  exif?: boolean,
  writeExif?: boolean | { [name: string]: any },
  width?: number,
  fixOrientation?: boolean,
  forceUpOrientation?: boolean,
  pauseAfterCapture?: boolean,
};

type EventCallbackArgumentsType = {
  nativeEvent: Object,
};

type Rect = {
  x: number,
  y: number,
  width: number,
  height: number,
};

type PropsType = typeof View.props & {
  zoom?: number,
  maxZoom?: number,
  ratio?: string,
  focusDepth?: number,
  type?: number | string,
  onCameraReady?: Function,
  onStatusChange?: Function,
  onPictureTaken?: Function,
  onPictureSaved?: Function,
  onSubjectAreaChanged?: ({ nativeEvent: { prevPoint: {| x: number, y: number |} } }) => void,
  flashMode?: number | string,
  exposure?: number,
  whiteBalance?: number | string,
  colorEffect?: number | string,
  autoFocus?: string | boolean | number,
  autoFocusPointOfInterest?: { x: number, y: number },
  useCamera2Api?: boolean,
  playSoundOnCapture?: boolean,
  pictureSize?: string,
  rectOfInterest: Rect,
};

type StateType = {
  isAuthorized: boolean,
  isAuthorizationChecked: boolean,
};

export type Status = 'READY' | 'PENDING_AUTHORIZATION' | 'NOT_AUTHORIZED';

const CameraStatus: { [key: Status]: Status } = {
  READY: 'READY',
  PENDING_AUTHORIZATION: 'PENDING_AUTHORIZATION',
  NOT_AUTHORIZED: 'NOT_AUTHORIZED',
};

const CameraManager: Object = NativeModules.RNCameraManager ||
  NativeModules.RNCameraModule || {
    stubbed: true,
    Type: {
      back: 1,
    },
    AutoFocus: {
      on: 1,
    },
    FlashMode: {
      off: 1,
    },
    WhiteBalance: {},
    ColorEffect: {},
  };

const EventThrottleMs = 500;

const mapValues = (input, mapper) => {
  const result = {};
  Object.entries(input).map(([key, value]) => {
    result[key] = mapper(value, key);
  });
  return result;
};

export default class Camera extends React.Component<PropsType, StateType> {
  static Constants = {
    Type: CameraManager.Type,
    FlashMode: CameraManager.FlashMode,
    AutoFocus: CameraManager.AutoFocus,
    WhiteBalance: CameraManager.WhiteBalance,
    ColorEffect: Platform.OS === 'ios' ? undefined : CameraManager.ColorEffect,
    Orientation: {
      auto: 'auto',
      landscapeLeft: 'landscapeLeft',
      landscapeRight: 'landscapeRight',
      portrait: 'portrait',
      portraitUpsideDown: 'portraitUpsideDown',
    },
  };

  // Values under keys from this object will be transformed to native options
  static ConversionTables = {
    type: CameraManager.Type,
    flashMode: CameraManager.FlashMode,
    exposure: CameraManager.Exposure,
    autoFocus: CameraManager.AutoFocus,
    whiteBalance: CameraManager.WhiteBalance,
    colorEffect: Platform.OS === 'ios' ? undefined : CameraManager.ColorEffect,
  };

  static propTypes = {
    ...ViewPropTypes,
    zoom: PropTypes.number,
    maxZoom: PropTypes.number,
    ratio: PropTypes.string,
    focusDepth: PropTypes.number,
    onMountError: PropTypes.func,
    onCameraReady: PropTypes.func,
    onStatusChange: PropTypes.func,
    onPictureTaken: PropTypes.func,
    onPictureSaved: PropTypes.func,
    onSubjectAreaChanged: PropTypes.func,
    type: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    cameraId: PropTypes.string,
    flashMode: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    exposure: PropTypes.number,
    whiteBalance: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    colorEffect: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    autoFocus: PropTypes.oneOfType([PropTypes.string, PropTypes.number, PropTypes.bool]),
    autoFocusPointOfInterest: PropTypes.shape({ x: PropTypes.number, y: PropTypes.number }),
    permissionDialogTitle: PropTypes.string,
    permissionDialogMessage: PropTypes.string,
    androidCameraPermissionOptions: Rationale,
    notAuthorizedView: PropTypes.element,
    pendingAuthorizationView: PropTypes.element,
    useCamera2Api: PropTypes.bool,
    playSoundOnCapture: PropTypes.bool,
    pictureSize: PropTypes.string,
    rectOfInterest: PropTypes.any,
  };

  static defaultProps: Object = {
    zoom: 0,
    maxZoom: 0,
    ratio: '4:3',
    focusDepth: 0,
    type: CameraManager.Type.back,
    cameraId: null,
    autoFocus: CameraManager.AutoFocus.on,
    flashMode: CameraManager.FlashMode.off,
    exposure: -1,
    whiteBalance: CameraManager.WhiteBalance.auto,
    colorEffect: Platform.OS === 'ios' ? undefined : CameraManager.ColorEffect.off,
    permissionDialogTitle: '',
    permissionDialogMessage: '',
    androidCameraPermissionOptions: {
      title: '',
      message: '',
    },
    notAuthorizedView: (
      <View style={styles.authorizationContainer}>
        <Text style={styles.notAuthorizedText}>Camera not authorized</Text>
      </View>
    ),
    pendingAuthorizationView: (
      <View style={styles.authorizationContainer}>
        <ActivityIndicator size="small" />
      </View>
    ),
    useCamera2Api: false,
    playSoundOnCapture: false,
    pictureSize: 'None',
  };

  _cameraRef: ?Object;
  _cameraHandle: ?number;
  _lastEvents: { [string]: string };
  _lastEventsTimes: { [string]: Date };
  _isMounted: boolean;

  constructor(props: PropsType) {
    super(props);
    this._lastEvents = {};
    this._lastEventsTimes = {};
    this._isMounted = true;
    this.state = {
      isAuthorized: false,
      isAuthorizationChecked: false,
    };
  }

  async takePictureAsync(options?: PictureOptions) {
    if (!options) {
      options = {};
    }
    if (!options.quality) {
      options.quality = 1;
    }

    if (options.orientation) {
      if (typeof options.orientation !== 'number') {
        const { orientation } = options;
        options.orientation = CameraManager.Orientation[orientation];
        if (__DEV__) {
          if (typeof options.orientation !== 'number') {
            // eslint-disable-next-line no-console
            console.warn(`Orientation '${orientation}' is invalid.`);
          }
        }
      }
    }

    if (options.pauseAfterCapture === undefined) {
      options.pauseAfterCapture = false;
    }

    if (!this._cameraHandle) {
      throw 'Camera handle cannot be null';
    }

    return await CameraManager.takePicture(options, this._cameraHandle);
  }

  async getSupportedRatiosAsync() {
    if (Platform.OS === 'android') {
      return await CameraManager.getSupportedRatios(this._cameraHandle);
    } else {
      throw new Error('Ratio is not supported on iOS');
    }
  }

  async getCameraIdsAsync() {
    if (Platform.OS === 'android') {
      return await CameraManager.getCameraIds(this._cameraHandle);
    } else {
      return await CameraManager.getCameraIds(); // iOS does not need a camera instance
    }
  }

  getAvailablePictureSizes = async (): string[] => {
    //$FlowFixMe
    return await CameraManager.getAvailablePictureSizes(this.props.ratio, this._cameraHandle);
  };

  pausePreview() {
    CameraManager.pausePreview(this._cameraHandle);
  }

  resumePreview() {
    CameraManager.resumePreview(this._cameraHandle);
  }

  _onMountError = ({ nativeEvent }: EventCallbackArgumentsType) => {
    if (this.props.onMountError) {
      this.props.onMountError(nativeEvent);
    }
  };

  _onCameraReady = () => {
    if (this.props.onCameraReady) {
      this.props.onCameraReady();
    }
  };

  _onStatusChange = () => {
    if (this.props.onStatusChange) {
      this.props.onStatusChange({
        cameraStatus: this.getStatus(),
      });
    }
  };

  _onPictureSaved = ({ nativeEvent }: EventCallbackArgumentsType) => {
    if (this.props.onPictureSaved) {
      this.props.onPictureSaved(nativeEvent);
    }
  };

  _onObjectDetected = (callback: ?Function) => ({ nativeEvent }: EventCallbackArgumentsType) => {
    const { type } = nativeEvent;
    if (
      this._lastEvents[type] &&
      this._lastEventsTimes[type] &&
      JSON.stringify(nativeEvent) === this._lastEvents[type] &&
      new Date() - this._lastEventsTimes[type] < EventThrottleMs
    ) {
      return;
    }

    if (callback) {
      callback(nativeEvent);
      this._lastEventsTimes[type] = new Date();
      this._lastEvents[type] = JSON.stringify(nativeEvent);
    }
  };

  _onSubjectAreaChanged = e => {
    if (this.props.onSubjectAreaChanged) {
      this.props.onSubjectAreaChanged(e);
    }
  };

  _setReference = (ref: ?Object) => {
    if (ref) {
      this._cameraRef = ref;
      this._cameraHandle = findNodeHandle(ref);
    } else {
      this._cameraRef = null;
      this._cameraHandle = null;
    }
  };

  componentWillUnmount() {
    this._isMounted = false;
  }

  async arePermissionsGranted() {
    const {
      permissionDialogTitle,
      permissionDialogMessage,
      androidCameraPermissionOptions,
    } = this.props;

    let cameraPermissions = androidCameraPermissionOptions;
    if (permissionDialogTitle || permissionDialogMessage) {
      // eslint-disable-next-line no-console
      console.warn(
        'permissionDialogTitle and permissionDialogMessage are deprecated. Please use androidCameraPermissionOptions instead.',
      );
      cameraPermissions = {
        ...cameraPermissions,
        title: permissionDialogTitle,
        message: permissionDialogMessage,
      };
    }

    const { hasCameraPermissions } = await requestPermissions(CameraManager, cameraPermissions);

    return { hasCameraPermissions };
  }

  async refreshAuthorizationStatus() {
    const { hasCameraPermissions } = await this.arePermissionsGranted();
    if (this._isMounted === false) {
      return;
    }

    this.setState({
      isAuthorized: hasCameraPermissions,
      isAuthorizationChecked: true,
    });
  }

  async componentDidMount() {
    const { hasCameraPermissions } = await this.arePermissionsGranted();
    if (this._isMounted === false) {
      return;
    }

    this.setState(
      {
        isAuthorized: hasCameraPermissions,
        isAuthorizationChecked: true,
      },
      this._onStatusChange,
    );
  }

  getStatus = (): Status => {
    const { isAuthorized, isAuthorizationChecked } = this.state;
    if (isAuthorizationChecked === false) {
      return CameraStatus.PENDING_AUTHORIZATION;
    }
    return isAuthorized ? CameraStatus.READY : CameraStatus.NOT_AUTHORIZED;
  };

  // FaCC = Function as Child Component;
  hasFaCC = (): * => typeof this.props.children === 'function';

  renderChildren = (): * => {
    if (this.hasFaCC()) {
      return this.props.children({
        camera: this,
        status: this.getStatus(),
      });
    }
    return this.props.children;
  };

  render() {
    const { style, ...nativeProps } = this._convertNativeProps(this.props);

    if (this.state.isAuthorized || this.hasFaCC()) {
      return (
        <View style={style}>
          <RNCamera
            {...nativeProps}
            style={StyleSheet.absoluteFill}
            ref={this._setReference}
            onMountError={this._onMountError}
            onCameraReady={this._onCameraReady}
            onPictureSaved={this._onPictureSaved}
            onSubjectAreaChanged={this._onSubjectAreaChanged}
          />
          {this.renderChildren()}
        </View>
      );
    } else if (!this.state.isAuthorizationChecked) {
      return this.props.pendingAuthorizationView;
    } else {
      return this.props.notAuthorizedView;
    }
  }

  _convertNativeProps({ children, ...props }: PropsType) {
    const newProps = mapValues(props, this._convertProp);

    if (Platform.OS === 'ios') {
      delete newProps.ratio;
    }

    return newProps;
  }

  _convertProp(value: *, key: string): * {
    if (typeof value === 'string' && Camera.ConversionTables[key]) {
      return Camera.ConversionTables[key][value];
    }

    return value;
  }
}

export const Constants = Camera.Constants;

const RNCamera = requireNativeComponent('RNCamera', Camera, {
  nativeOnly: {
    accessibilityComponentType: true,
    accessibilityLabel: true,
    accessibilityLiveRegion: true,
    importantForAccessibility: true,
    onCameraReady: true,
    onPictureSaved: true,
    onLayout: true,
    onMountError: true,
    onSubjectAreaChanged: true,
    renderToHardwareTextureAndroid: true,
    testID: true,
  },
});
