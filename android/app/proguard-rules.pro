# Flutter specific ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Keep Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

# Flutter Quill
-keep class com.quilljs.** { *; }

# Archive package
-keep class org.apache.commons.compress.** { *; }

# Image compress
-keep class com.flutterimagecompress.** { *; }

# Encrypt package
-keep class com.example.encrypt.** { *; }

# General rules for reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
