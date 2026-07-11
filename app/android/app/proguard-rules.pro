# ML Kit text recognition (OCR): бандлим только латиницу. Классы распознавателей
# CJK/деванагари не входят в сборку — глушим предупреждения R8, иначе
# minifyRelease падает на «Missing class». Расширение на эти скрипты = добавить
# зависимости com.google.mlkit:text-recognition-<script> в этот модуль.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
