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

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Encrypt package (encrypt: ^5.0.3)
-keep class com.example.encrypt.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Archive package (archive: ^4.0.4)
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**

# Flutter Image Compress (flutter_image_compress: ^2.4.0)
-keep class com.flutterimagecompress.** { *; }
-keep class com.pngencoder.** { *; }

# Video Player (video_player: ^2.8.6)
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# File Picker (file_picker: ^10.3.7)
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Share Plus (share_plus: ^12.0.1)
-keep class dev.fluttercommunity.plus.share.** { *; }

# Path Provider (path_provider: ^2.1.5)
-keep class io.flutter.plugins.pathprovider.** { *; }

# PDF rendering (pdfx: ^2.6.0)
-keep class io.scer.pdfx.** { *; }

# AppFlowy Editor (appflowy_editor: ^6.2.0) - pure Dart, no native code
# No specific rules needed

# General rules for reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses,EnclosingMethod

# Keep R8 compatible with Kotlin
-dontwarn kotlin.**
-keep class kotlin.Metadata { *; }
