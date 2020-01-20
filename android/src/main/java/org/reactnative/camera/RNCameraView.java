package org.reactnative.camera;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.media.MediaActionSound;
import android.os.AsyncTask;
import android.os.Build;
import android.view.View;

import androidx.core.content.ContextCompat;

import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.uimanager.ThemedReactContext;
import com.google.android.cameraview.CameraView;

import org.reactnative.camera.tasks.PictureSavedDelegate;
import org.reactnative.camera.tasks.ResolveTakenPictureAsyncTask;

import java.io.File;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;

public class RNCameraView extends CameraView implements LifecycleEventListener, PictureSavedDelegate {
    private ThemedReactContext mThemedReactContext;
    private Queue<Promise> mPictureTakenPromises = new ConcurrentLinkedQueue<>();
    private Map<Promise, ReadableMap> mPictureTakenOptions = new ConcurrentHashMap<>();
    private Map<Promise, File> mPictureTakenDirectories = new ConcurrentHashMap<>();
    private Boolean mPlaySoundOnCapture = false;

    private boolean mIsPaused = false;
    private boolean mIsNew = true;

    public RNCameraView(ThemedReactContext themedReactContext) {
        super(themedReactContext, true);
        mThemedReactContext = themedReactContext;
        themedReactContext.addLifecycleEventListener(this);

        addCallback(new Callback() {
            @Override
            public void onCameraOpened(CameraView cameraView) {
                RNCameraViewHelper.emitCameraReadyEvent(cameraView);
            }

            @Override
            public void onMountError(CameraView cameraView) {
                RNCameraViewHelper.emitMountErrorEvent(cameraView, "Camera view threw an error - component could not be rendered.");
            }

            @Override
            public void onPictureTaken(CameraView cameraView, final byte[] data, int deviceOrientation) {
                Promise promise = mPictureTakenPromises.poll();
                ReadableMap options = mPictureTakenOptions.remove(promise);
                if (options.hasKey("fastMode") && options.getBoolean("fastMode")) {
                    promise.resolve(null);
                }
                final File cacheDirectory = mPictureTakenDirectories.remove(promise);

                new ResolveTakenPictureAsyncTask(data, promise, options, cacheDirectory, deviceOrientation, RNCameraView.this)
                        .executeOnExecutor(AsyncTask.THREAD_POOL_EXECUTOR);

                RNCameraViewHelper.emitPictureTakenEvent(cameraView);
            }
        });
    }

    @Override
    protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        View preview = getView();
        if (null == preview) {
            return;
        }
        float width = right - left;
        float height = bottom - top;
        float ratio = getAspectRatio().toFloat();
        int orientation = getResources().getConfiguration().orientation;
        int correctHeight;
        int correctWidth;
        this.setBackgroundColor(Color.BLACK);
        if (orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) {
            if (ratio * height < width) {
                correctHeight = (int) (width / ratio);
                correctWidth = (int) width;
            } else {
                correctWidth = (int) (height * ratio);
                correctHeight = (int) height;
            }
        } else {
            if (ratio * width > height) {
                correctHeight = (int) (width * ratio);
                correctWidth = (int) width;
            } else {
                correctWidth = (int) (height / ratio);
                correctHeight = (int) height;
            }
        }
        int paddingX = (int) ((width - correctWidth) / 2);
        int paddingY = (int) ((height - correctHeight) / 2);
        preview.layout(paddingX, paddingY, correctWidth + paddingX, correctHeight + paddingY);
    }

    @SuppressLint("all")
    @Override
    public void requestLayout() {
        // React handles this for us, so we don't need to call super.requestLayout();
    }

    public void setPlaySoundOnCapture(Boolean playSoundOnCapture) {
        mPlaySoundOnCapture = playSoundOnCapture;
    }

    public void takePicture(final ReadableMap options, final Promise promise, final File cacheDirectory) {
        mBgHandler.post(new Runnable() {
            @Override
            public void run() {
                mPictureTakenPromises.add(promise);
                mPictureTakenOptions.put(promise, options);
                mPictureTakenDirectories.put(promise, cacheDirectory);
                if (mPlaySoundOnCapture) {
                    MediaActionSound sound = new MediaActionSound();
                    sound.play(MediaActionSound.SHUTTER_CLICK);
                }
                try {
                    RNCameraView.super.takePicture(options);
                } catch (Exception e) {
                    mPictureTakenPromises.remove(promise);
                    mPictureTakenOptions.remove(promise);
                    mPictureTakenDirectories.remove(promise);

                    promise.reject("E_TAKE_PICTURE_FAILED", e.getMessage());
                }
            }
        });
    }

    @Override
    public void onPictureSaved(WritableMap response) {
        RNCameraViewHelper.emitPictureSavedEvent(this, response);
    }


    @Override
    public void onHostResume() {
        if (hasCameraPermissions()) {
            mBgHandler.post(new Runnable() {
                @Override
                public void run() {
                    if ((mIsPaused && !isCameraOpened()) || mIsNew) {
                        mIsPaused = false;
                        mIsNew = false;
                        stop();
                        start();
                    }
                }
            });
        } else {
            RNCameraViewHelper.emitMountErrorEvent(this, "Camera permissions not granted - component could not be rendered.");
        }
    }

    @Override
    public void onHostPause() {
        if (!mIsPaused && isCameraOpened()) {
            mIsPaused = true;
            stop();
        }
    }

    @Override
    public void onHostDestroy() {
        stop();
        mThemedReactContext.removeLifecycleEventListener(this);

        this.cleanup();
    }

    private boolean hasCameraPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            int result = ContextCompat.checkSelfPermission(getContext(), Manifest.permission.CAMERA);
            return result == PackageManager.PERMISSION_GRANTED;
        } else {
            return true;
        }
    }
}
