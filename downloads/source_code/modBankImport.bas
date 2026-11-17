Attribute VB_Name = "modBankImport"
Option Explicit

' Independently designed and implemented by the author on synthetic data.
' Not an export of any employer's workbook.
' Business rules, data design and acceptance testing by the author;
' AI assisted coding and documentation.

Public Sub Bank_Import()
    Dim wsS As Worksheet, wsT As Worksheet, wbT As Workbook, lo As ListObject, k As Range, pt As PivotTable
    Dim hr As Long, sc As Long, ec As Long, n As Long, nSrc As Long, c As Long, q As Long
    Dim oldLast As Long, fl As Long, nF As Long, nNo As Long, noF As String
    Dim fcol(1 To 80) As Long, fml(1 To 80) As String, calcMode As Long, failed As Boolean, e As String
    On Error Resume Next
    Set wsS = ThisWorkbook.Worksheets(Cfg(15))
    Set wbT = FindBook(Cfg(3))
    If Not wbT Is Nothing Then Set wsT = wbT.Worksheets(Cfg(16))
    On Error GoTo 0
    If wsS Is Nothing Or wbT Is Nothing Or wsT Is Nothing Then MsgBox "BANK source or target not found.", vbExclamation: Exit Sub
    If wsS.ListObjects.Count = 0 Then MsgBox "No query table on BANK source.", vbExclamation: Exit Sub
    Set lo = wsS.ListObjects(1)
    calcMode = Application.Calculation: Application.ScreenUpdating = False
    On Error GoTo EH
    On Error Resume Next
    lo.QueryTable.Refresh BackgroundQuery:=False
    If Err.Number <> 0 Then failed = True: e = Err.Description
    Err.Clear: On Error GoTo EH
    If failed Then Err.Raise 1100, , "Query refresh failed: " & e
    If lo.DataBodyRange Is Nothing Then Err.Raise 1101, , "Query returned 0 rows."
    n = lo.DataBodyRange.Rows.Count: nSrc = lo.ListColumns.Count
    If n = 1 And Len(CStr(lo.DataBodyRange.Cells(1, 1).Value)) = 0 Then Err.Raise 1101, , "Query returned 0 rows."
    Set k = wsT.Range("A1:AZ60").Find(Cfg(17), LookIn:=xlValues, LookAt:=xlWhole, SearchOrder:=xlByRows)
    If k Is Nothing Then Err.Raise 1102, , "First pasted header not found."
    hr = k.Row: sc = k.Column: ec = sc + nSrc - 1
    If Trim$(CStr(wsT.Cells(hr, ec).Value)) <> Cfg(18) Then Err.Raise 1105, , "Last pasted header mismatch."
    If wsT.FilterMode Then wsT.ShowAllData
    c = sc - 1
    Do While c >= 1 And c >= sc - 40
        If Len(Trim$(CStr(wsT.Cells(hr, c).Value))) = 0 Then Exit Do
        If wsT.Cells(hr + 1, c).HasFormula Then
            nF = nF + 1: fcol(nF) = c: fml(nF) = wsT.Cells(hr + 1, c).FormulaR1C1
        Else
            nNo = nNo + 1: noF = noF & IIf(nNo = 1, "", ", ") & ColLetter(c) & " " & wsT.Cells(hr, c).Value
        End If
        c = c - 1
    Loop
    c = ec + 1
    Do While c <= ec + 40
        If Len(Trim$(CStr(wsT.Cells(hr, c).Value))) = 0 Then Exit Do
        If wsT.Cells(hr + 1, c).HasFormula Then
            nF = nF + 1: fcol(nF) = c: fml(nF) = wsT.Cells(hr + 1, c).FormulaR1C1
        Else
            nNo = nNo + 1: noF = noF & IIf(nNo = 1, "", ", ") & ColLetter(c) & " " & wsT.Cells(hr, c).Value
        End If
        c = c + 1
    Loop
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
    On Error Resume Next
    wsT.Range(Cfg(20)).NumberFormat = "yyyy/m/d": wsT.Range(Cfg(20)).Value = Date
    wsT.Range(Cfg(21)).NumberFormat = "h:mm": wsT.Range(Cfg(21)).Value = Time
    For Each pt In wsT.PivotTables: pt.RefreshTable: Next pt
    On Error GoTo EH
    Application.Calculation = calcMode: Application.ScreenUpdating = True
    e = "BANK import done: " & n & " rows x " & nSrc & " cols."
    If nNo > 0 Then e = e & vbLf & "Headed neighbour columns with no formula: " & noF
    MsgBox e, vbInformation
    Exit Sub
EH:
    Application.CutCopyMode = False
    Application.Calculation = calcMode: Application.ScreenUpdating = True
    MsgBox "Error: " & Err.Description, vbCritical
End Sub