# Quillpad בעברית

חבילת בנייה עבור Quillpad 1.5.15 עם ממשק עברי.

## בנייה ב-Windows

פתח CMD והרץ פקודה אחת:

```cmd
git clone https://github.com/a0527198150-del/quillpad-hebrew.git && cd quillpad-hebrew && BUILD.cmd
```

הסקריפט מוריד את קוד המקור הרשמי של Quillpad, מוסיף תרגום לעברית ותמיכה בבחירת השפה ומריץ `:app:assembleDebug` באמצעות Gradle. ה-APK יתקבל בשם `Quillpad-Hebrew-debug.apk`.

נדרש Git, PowerShell, Java 17, Android SDK עם SDK Platform API 37, והרשאות גישה לתלויות Gradle. הרצת הבנייה הראשונה עשויה להזדקק לגישה לאינטרנט, ולא מובטח שסינון אינטרנט יאפשר הורדת כל התלויות.

**זהו תרגום קהילתי לא רשמי. הבנייה לא נבדקה מקצה לקצה.** בנייה בחתימת Debug אינה יכולה להחליף ישירות אפליקציה רשמית בחתימה שונה; לפני הסרה של גרסה קיימת יש לגבות פתקים.

קוד מקור מקורי: https://github.com/quillpad/quillpad (GPL-3.0).
