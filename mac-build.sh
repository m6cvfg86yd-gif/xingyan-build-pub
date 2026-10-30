set -e
cd "$(dirname "$0")"

APP="Payload/CHRISChat.app"
DIST="dist"
mkdir -p "$DIST"

echo "=== 0) 选 Xcode ==="
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode 还没设成命令行默认，切一下（可能要输一次 Mac 开机密码）："
  sudo xcode-select -s /Applications/Xcode.app 2>/dev/null || true
fi
xcodebuild -version || true
if ! SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" || [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  echo
  echo "❌ 这台 Mac 上找不到 iOS SDK —— 说明还没装 Xcode。"
  echo "   去 App Store 搜 Xcode 装上（约 10GB），装完再跑一次这个脚本。"
  exit 1
fi
echo "SDK = $SDK"

echo "=== 1) WebRTC（通话用，第一次要下 ~90MB）==="
if [ ! -d WebRTCKit/WebRTC.xcframework ]; then
  rm -rf WebRTCKit && mkdir -p WebRTCKit
  if ! curl -L --fail --retry 2 --connect-timeout 15 --max-time 240 -o /tmp/webrtc.zip \
      https://aa.x8iu.com/webrtc/WebRTC-M153.xcframework.zip; then
    curl -L --fail --retry 5 --connect-timeout 15 --max-time 900 -o /tmp/webrtc.zip \
      https://github.com/stasel/WebRTC/releases/download/153.0.0/WebRTC-M153.xcframework.zip
  fi
  unzip -q /tmp/webrtc.zip -d WebRTCKit
fi
ls WebRTCKit/WebRTC.xcframework/ios-arm64/WebRTC.framework >/dev/null

echo "=== 2) 腾讯云 TRTC ==="
if [ ! -d TRTCKit/TXLiteAVSDK_TRTC.framework ]; then
  rm -rf /tmp/trtc-x TRTCKit && mkdir -p /tmp/trtc-x TRTCKit
  curl -L --fail -o /tmp/trtc.zip https://liteav.sdk.qcloud.com/download/latest/TXLiteAVSDK_TRTC_iOS_latest.zip
  unzip -q /tmp/trtc.zip -d /tmp/trtc-x
  for NAME in TXLiteAVSDK_TRTC TXFFmpeg TXSoundTouch; do
    FW="$(find /tmp/trtc-x -type d -name "$NAME.framework" -path '*ios-arm64_armv7*' | head -1)"
    if [ -z "$FW" ]; then echo "没找到 $NAME 的设备片"; exit 1; fi
    cp -R "$FW" TRTCKit/
  done
fi
ls TRTCKit >/dev/null

echo "=== 3) 版本号 / 时间（写进 Info.plist，关于页会显示）==="
PREV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist 2>/dev/null || echo 0)"
if [ -n "$1" ]; then BUILDNO="$1"; else BUILDNO=$((PREV + 1)); fi
BUILDDATE="$(TZ=Asia/Shanghai date '+%m-%d %H:%M')"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILDNO" Info.plist || true
/usr/libexec/PlistBuddy -c "Add :BuildDate string $BUILDDATE" Info.plist \
  || /usr/libexec/PlistBuddy -c "Set :BuildDate $BUILDDATE" Info.plist || true
echo "版本 $BUILDNO · $BUILDDATE"

echo "=== 4) 拼 App 目录 ==="
rm -rf Payload && mkdir -p "$APP/Frameworks"
cp Info.plist "$APP/Info.plist"
cp AppIcon60x60@2x.png AppIcon60x60@3x.png "$APP/" 2>/dev/null || true
[ -f splash.jpg ] && cp splash.jpg "$APP/"
[ -f moments-cover.jpg ] && cp moments-cover.jpg "$APP/"
[ -d levelicons ] && cp levelicons/*.png "$APP/" 2>/dev/null || true

if [ -d Assets.xcassets ]; then
  xcrun actool Assets.xcassets --compile "$APP" --platform iphoneos \
    --target-device iphone --minimum-deployment-target 16.0 \
    --output-format human-readable-text >/dev/null 2>&1 \
    || echo "actool 跳过：启动屏用系统默认底色"
fi

if [ -f Sources/VoiceOrb.metal ]; then
  if xcrun -sdk iphoneos metal -c Sources/VoiceOrb.metal -o /tmp/VoiceOrb.air 2>/dev/null; then
    xcrun -sdk iphoneos metallib /tmp/VoiceOrb.air -o "$APP/default.metallib" 2>/dev/null || true
  fi
fi
if [ ! -f "$APP/default.metallib" ]; then
  echo "（这台 Xcode 没装 Metal Toolchain，取现成的 default.metallib）"
  curl -fsSL --max-time 60 -o "$APP/default.metallib" https://aa.x8iu.com/mac/default.metallib || true
fi
ls -lh "$APP/default.metallib" 2>/dev/null || echo "（没有 metallib，语音球会退回低配画法，不影响出包）"

cp -R WebRTCKit/WebRTC.xcframework/ios-arm64/WebRTC.framework "$APP/Frameworks/WebRTC.framework"
for NAME in TXLiteAVSDK_TRTC TXFFmpeg TXSoundTouch; do
  cp -R "TRTCKit/$NAME.framework" "$APP/Frameworks/$NAME.framework"
  lipo -thin arm64 "$APP/Frameworks/$NAME.framework/$NAME" \
    -output "$APP/Frameworks/$NAME.framework/$NAME.arm64" 2>/dev/null || true
  if [ -f "$APP/Frameworks/$NAME.framework/$NAME.arm64" ]; then
    mv "$APP/Frameworks/$NAME.framework/$NAME.arm64" "$APP/Frameworks/$NAME.framework/$NAME"
  fi
  rm -rf "$APP/Frameworks/$NAME.framework/_CodeSignature"
done

echo "=== 5) 编译原生 App（十几分钟，第一次最慢）==="
xcrun --sdk iphoneos swiftc \
  -sdk "$SDK" \
  -target arm64-apple-ios16.0 \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  -F "$SDK/System/Library/Frameworks" \
  -F WebRTCKit/WebRTC.xcframework/ios-arm64 \
  -F TRTCKit \
  -o "$APP/CHRIS" \
  Sources/*.swift \
  -framework SwiftUI -framework UIKit -framework Foundation \
  -framework LocalAuthentication -framework AVFoundation \
  -framework WebRTC \
  -framework TXLiteAVSDK_TRTC \
  -framework AudioToolbox -framework CoreTelephony -framework CoreMedia \
  -framework MediaPlayer \
  -framework CoreVideo -framework VideoToolbox -framework MetalKit -framework Metal \
  -framework Accelerate -framework SystemConfiguration -framework ReplayKit \
  -framework CoreGraphics -framework QuartzCore -framework OpenGLES \
  -framework Security -framework CryptoKit \
  -Xlinker -dead_strip \
  -lz -lsqlite3 -lc++ \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks 2>&1 | tee /tmp/mac-build.log

if grep -q "error:" /tmp/mac-build.log; then
  echo "==== 编译错误 ===="
  grep -E "error:" /tmp/mac-build.log | head -40
  exit 1
fi

echo "=== 6) 瘦身 + 打包 ==="
for NAME in WebRTC TXLiteAVSDK_TRTC TXFFmpeg TXSoundTouch; do
  rm -rf "$APP/Frameworks/$NAME.framework/Headers" \
         "$APP/Frameworks/$NAME.framework/Modules" \
         "$APP/Frameworks/$NAME.framework/PrivateHeaders"
  [ -f "$APP/Frameworks/$NAME.framework/$NAME" ] && strip -x -S "$APP/Frameworks/$NAME.framework/$NAME" || true
done
strip -x -S "$APP/CHRIS" || true

OUT="$DIST/星言-unsigned.ipa"
rm -f "$OUT"
zip -qry "$OUT" Payload
ls -lh "$OUT"
echo "SHA256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
echo
echo "本地这一份：$(pwd)/$OUT（未签名，用爱思助手自己签）"

UPLOAD_KEY="${XY_MAC_UPLOAD_KEY:-}"
if [ -n "$UPLOAD_KEY" ] && [ -f "$OUT" ]; then
  echo "=== 7) 回传到服务器（aa.x8iu.com）… ==="
  curl -sS --max-time 600 -X POST --data-binary "@$OUT" \
    -H "Content-Type: application/octet-stream" \
    "https://aa.x8iu.com/api/mac-build/$UPLOAD_KEY" || true
  echo
  echo "（上面那行 JSON 里 ok:true 就说明服务器收到了）"
fi
