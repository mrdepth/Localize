# Localize

Localize is the utility that is designed to simplify the work with translations. Localize is embedded in the XCode project as a separate target and synchronizes the translations with Google Sheet.

### Installation
1. Turn on the Google Sheets API https://developers.google.com/sheets/api/quickstart/ios?authuser=1
2. Create blank Google Sheet Document and make it shared by link
3. Add **Localize.xcodeproj** from this repository to your Workspace
4. Add **External Build System** target to your project
   1. Change **SDKROOT** build setting to **macosx**
   2. Build Tool: **Localize/localize.sh**
   3. Arguments: **-spreadsheet *spreadsheetID* [-languages "de es fr it ja ko nl pt-BR pt ru"]  -clientID *clientID* -clientSecret *clientSecret***
  
    > You can find spreadsheetID in the Google Sheet's url
    > docs.google.com/spreadsheets/d/**1ebxmnfNck3IRrTPDXXX_XXbKoSMooMfMSz54RAn8XTCC4**/edit#gid=0

You can now build this target to sync translations with Google Sheets
