Attribute VB_Name = "modAPImport"
Option Explicit

' Independently designed and implemented by the author on synthetic data.
' Not an export of any employer's workbook.
' Business rules, data design and acceptance testing by the author;
' AI assisted coding and documentation.

Public Sub Run_All()
    AR_Import
    AP_Import
    Bank_Import
End Sub

Public Sub AP_Import()
    Dim wsS As Worksheet, wsT As Worksheet, wbT As Workbook, lo As ListObject, k As Range, pt As PivotTable
    Dim hr As Long, sc As Long, ec As Long, n As Long, nSrc As Long
    Dim c As Long, q As Long, oldLast As Long, fl As Long, nF As Long
    Dim fcol(1 To 60) As Long, fml(1 To 60) As String, nDiff As Long, diff As String
    Dim calcMode As Long, failed As Boolean, e As String, fpath As String, stamp As Date, fromName As Boolean
    On Error Resume Next
    Set wsS = ThisWorkbook.Worksheets(Cfg(12))
    Set wbT = FindBook(Cfg(3))
    If Not wbT Is Nothing Then Set wsT = wbT.Worksheets(Cfg(13))
    On Error GoTo 0
    If wsS Is Nothing Then MsgBox "Source query sheet not found.", vbExclamation: Exit Sub
    If wbT Is Nothing Then MsgBox "Target workbook not open.", vbExclamation: Exit Sub
    If wsT Is Nothing Then MsgBox "Target sheet not found.", vbExclamation: Exit Sub
    If wsS.ListObjects.Count = 0 Then MsgBox "No query table on source sheet.", vbExclamation: Exit Sub
    If Len(Cfg(19)) = 0 Then MsgBox "AP file prefix is empty.", vbExclamation: Exit Sub
    Set lo = wsS.ListObjects(1)
    fpath = LatestTxt(Cfg(2) & "\AP\", Cfg(19))
    If fpath = "" Then MsgBox "No AP txt file found.", vbExclamation: Exit Sub
    fromName = StampFromName(FileNameOf(fpath), stamp)
    If Not fromName Then stamp = FileDateTime(fpath)
    calcMode = Application.Calculation
    Application.ScreenUpdating = False
    On Error GoTo EH
    On Error Resume Next
    lo.QueryTable.Refresh BackgroundQuery:=False
    If Err.Number <> 0 Then failed = True: e = Err.Description
    Err.Clear: On Error GoTo EH
    If failed Then Err.Raise 1100, , "Query refresh failed: " & e
    If lo.DataBodyRange Is Nothing Then Err.Raise 1101, , "Query returned 0 rows."
    n = lo.DataBodyRange.Rows.Count: nSrc = lo.ListColumns.Count
    Set k = wsT.Range("A1:AZ60").Find(Cfg(14), LookIn:=xlValues, LookAt:=xlWhole, SearchOrder:=xlByRows)
    If k Is Nothing Then Err.Raise 1102, , "First pasted header not found."
    hr = k.Row: sc = k.Column: ec = sc + nSrc - 1
    ' The final Query column is intentionally excluded from header comparison:
    ' Power Query appends "Source File" for traceability, while the target paste
    ' block may not contain that operational metadata header.
    For c = 1 To nSrc - 1
        If Trim$(CStr(lo.HeaderRowRange.Cells(1, c).Value)) <> Trim$(CStr(wsT.Cells(hr, sc + c - 1).Value)) Then
            nDiff = nDiff + 1: diff = diff & vbLf & "col " & c & ": " & wsT.Cells(hr, sc + c - 1).Value & " <> " & lo.HeaderRowRange.Cells(1, c).Value
        End If
    Next c
    If nDiff > 0 Then Err.Raise 1103, , nDiff & " header(s) differ. Nothing was pasted." & diff
    If wsT.FilterMode Then wsT.ShowAllData
    For c = ec + 1 To ec + 60
        If Len(Trim$(CStr(wsT.Cells(hr, c).Value))) = 0 Then Exit For
        If wsT.Cells(hr + 1, c).HasFormula Then nF = nF + 1: fcol(nF) = c: fml(nF) = wsT.Cells(hr + 1, c).FormulaR1C1
    Next c
    Application.Calculation = xlCalculationManual
    oldLast = hr + 1
    For c = sc To ec
        q = wsT.Cells(wsT.Rows.Count, c).End(xlUp).Row
        If q > oldLast Then oldLast = q
    Next c
    If oldLast < hr + n Then oldLast = hr + n
    wsT.Range(wsT.Cells(hr + 1, sc), wsT.Cells(oldLast, ec)).ClearContents
    lo.DataBodyRange.Copy
    wsT.Cells(hr + 1, sc).PasteSpecial Paste:=xlPasteValues
    Application.CutCopyMode = False
    For c = 1 To nF
        fl = wsT.Cells(wsT.Rows.Count, fcol(c)).End(xlUp).Row
        If fl < hr Then fl = hr
        If fl < hr + n Then wsT.Range(wsT.Cells(fl + 1, fcol(c)), wsT.Cells(hr + n, fcol(c))).FormulaR1C1 = fml(c)
        If CLEAR_LEFTOVER And fl > hr + n Then wsT.Range(wsT.Cells(hr + n + 1, fcol(c)), wsT.Cells(fl, fcol(c))).ClearContents
    Next c
    For Each pt In wsT.PivotTables: pt.RefreshTable: Next pt
    Application.Calculation = calcMode: Application.ScreenUpdating = True
    MsgBox "AP import done: " & n & " rows x " & nSrc & " cols." & vbLf & FileNameOf(fpath), vbInformation
    Exit Sub
EH:
    Application.CutCopyMode = False
    Application.Calculation = calcMode: Application.ScreenUpdating = True
    MsgBox "Error: " & Err.Description, vbCritical
End Sub