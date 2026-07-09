# Flutter / plugin ProGuard rules for release shrinking.

# Keep Flutter embedding.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# flutter_local_notifications (uses Gson serialization for scheduled notifications).
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Razorpay payments — keep SDK classes and annotations (per Razorpay docs).
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

# WorkManager (background expiry checks).
-keep class androidx.work.** { *; }
