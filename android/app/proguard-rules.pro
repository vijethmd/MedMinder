# Release-build shrinking rules.

# flutter_local_notifications saves scheduled reminders as JSON (Gson) and
# reads them back after a reboot or app update. Keep its classes and field
# names, otherwise saved reminders can't be read ("Missing type parameter").
-keep class com.dexterous.** { *; }

## Gson
# Gson needs generic type information, which R8 removes by default.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# android_alarm_manager_plus starts its background Dart code by class name.
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }
