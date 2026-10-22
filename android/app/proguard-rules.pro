# Agora RTC: JNI + reflection.
-keep class io.agora.** { *; }
-dontwarn io.agora.**
# flutter_callkit_incoming: CallkitConnection is looked up from MainActivity (Telecom routing),
# and its broadcast receiver / services are started by class name.
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
# flutter_secure_storage encrypts with Tink, which refers to annotation-only classes that are
# not on the Android classpath (CE).
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
# Razorpay checkout (razorpay_flutter): the SDK calls back through reflection and its JS
# bridge (Razorpay's documented keep rules).
-keepattributes *Annotation*
-keepattributes JavascriptInterface
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
