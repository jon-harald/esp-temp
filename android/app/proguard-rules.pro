# Firebase, Retrofit and OkHttp ship their own consumer ProGuard rules.
# kotlinx.serialization needs its serializers kept.

# Keep @Serializable classes + generated serializers.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class * {
    kotlinx.serialization.KSerializer serializer(...);
}

# Data-layer DTOs / domain models are (de)serialized reflectively / by field name.
-keep class no.brathen.esptemp.data.adafruit.** { *; }
-keep class no.brathen.esptemp.domain.model.** { *; }
