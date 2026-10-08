# gomobile: the Go runtime calls these classes by name through JNI, so R8 must not rename or strip them.
-keep class go.** { *; }
-keep class com.obsidian.core.mobile.** { *; }
-keep class com.obsidian.vpn.** { *; }
