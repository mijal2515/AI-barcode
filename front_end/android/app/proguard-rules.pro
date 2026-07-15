# mobile_scanner가 함께 제공하는 proguard-rules.pro는 "com.google.mlkit.*"(별표 1개)만
# keep하는데, 이는 하위 패키지(com.google.mlkit.vision.barcode.internal.* 등)를
# 보호하지 못해 release 빌드에서 MLKit 내부 클래스가 손상되어
# "Attempt to invoke virtual method ... on a null object reference" 크래시가 발생했다.
# "**"(별표 2개)로 모든 하위 패키지를 포함해 보호한다.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
