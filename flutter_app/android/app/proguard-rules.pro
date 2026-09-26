# flutter_local_notifications v18 + Gson
# R8 full mode can strip TypeToken generic signatures; keep them strictly.
# Do NOT use allowshrinking on TypeToken subclasses — that reintroduces the crash.

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-dontwarn sun.misc.**
-dontwarn com.google.gson.**

-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }

-keep class * extends com.google.gson.TypeAdapter { *; }
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }

-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Plugin models persisted via Gson for scheduled notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
