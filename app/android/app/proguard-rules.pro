# Flutter / plugin ProGuard rules for release shrinking.

# Keep Flutter embedding.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# flutter_local_notifications (uses Gson serialization for scheduled notifications).
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Keep Google Play Billing / in_app_purchase.
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# WorkManager (background expiry checks).
-keep class androidx.work.** { *; }
