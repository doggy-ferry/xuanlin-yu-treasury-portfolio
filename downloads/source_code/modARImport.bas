Attribute VB_Name = "modARImport"
Option Explicit

' Independently designed and implemented by the author on synthetic data.
' Not an export of any employer's workbook.
' Business rules, data design and acceptance testing by the author;
' AI assisted coding and documentation.

Public Sub AR_Import()
    Const TARGET_SHEET As String = "AR"
    Dim wbS As Workbook, wbT As Workbook, wsS As Worksheet, wsT As Worksheet
    Dim hr As Long, sc As Long, shr As Long, ssc As Long, raw As Variant, data() As Variant
    Dim path As String, stamp As Date, rawN As Long, nCol As Long, n As Long, skipped As Long
    Dim i As Long, c As Long, k As Long, dc As Long, m As Variant, diff As String
    Dim oldLast As Long, f1 As Long, f2 As Long, fl As Long, fml() As String
    Dim hasDate As Boolean, hasTime As Boolean, sDate As Variant, sTime As Variant
    Dim calcMode As Long, stampMsg As String

    On Error Resume Next
    Set wbT = FindBook(Cfg(3))
    If Not wbT Is Nothing Then Set wsT = wbT.Worksheets(TARGET_SHEET)
    On Error GoTo 0
    If wbT Is Nothing Then MsgBox "Target workbook is not open.", vbExclamation: Exit Sub
    If wsT Is Nothing Then MsgBox "Target AR sheet not found.", vbExclamation: Exit Sub
    If Not FindHeaders(wsT, hr, sc) Then MsgBox "Target headers not found.", vbExclamation: Exit Sub

    path = LatestFile(Cfg(2) & "\AR\", Cfg(5))
    If path = "" Then MsgBox "No AR file found.", vbExclamation: Exit Sub
    stamp = FileDateTime(path)
    calcMode = Application.Calculation
    Application.Calculation = xlCalculationManual
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False
    On Error GoTo EH

    Set wbS = Workbooks.Open(path, ReadOnly:=True)
    For Each wsS In wbS.Worksheets
        If FindHeaders(wsS, shr, ssc) Then Exit For
    Next wsS
    If shr = 0 Then Err.Raise 1001, , "Source headers not found."
    hasDate = GetLabelValue(wsS, shr - 1, Cfg(9), sDate)
    hasTime = GetLabelValue(wsS, shr - 1, Cfg(10), sTime)

    rawN = wsS.Cells(wsS.Rows.Count, ssc).End(xlUp).Row - shr
    If rawN <= 0 Then Err.Raise 1002, , "No data rows in AR file."
    nCol = 0
    Do While Len(CStr(wsS.Cells(shr, ssc + nCol).Value)) > 0: nCol = nCol + 1: Loop

    m = Application.Match(Cfg(8), wsS.Rows(shr), 0)
    If Not IsError(m) Then
        If CStr(wsS.Cells(shr + 1, m).Value) <> Cfg(4) Then Err.Raise 1003, , "Company code mismatch."
    End If
    For c = 0 To nCol - 1
        If Trim$(CStr(wsS.Cells(shr, ssc + c).Value)) <> Trim$(CStr(wsT.Cells(hr, sc + c).Value)) Then
            diff = diff & vbLf & wsT.Cells(hr, sc + c).Value & " <> " & wsS.Cells(shr, ssc + c).Value
        End If
    Next c
    If diff <> "" Then Err.Raise 1004, , "Column order differs:" & diff

    raw = wsS.Cells(shr + 1, ssc).Resize(rawN, nCol).Value
    wbS.Close False: Set wbS = Nothing
    dc = 0
    For c = 0 To nCol - 1
        If CStr(wsT.Cells(hr, sc + c).Value) = Cfg(6) Then dc = c + 1: Exit For
    Next c
    n = 0
    For i = 1 To rawN
        If Not IsError(raw(i, 1)) Then If Len(Trim$(CStr(raw(i, 1)))) > 0 Then n = n + 1
    Next i
    If n = 0 Then Err.Raise 1005, , "No non-blank data rows in AR file."
    skipped = rawN - n
    ReDim data(1 To n, 1 To nCol)
    k = 0
    For i = 1 To rawN
        If Not IsError(raw(i, 1)) Then
            If Len(Trim$(CStr(raw(i, 1)))) > 0 Then
                k = k + 1
                For c = 1 To nCol: data(k, c) = raw(i, c): Next c
                If dc > 0 Then If IsDate(data(k, dc)) Then data(k, dc) = Format$(CDate(data(k, dc)), "yyyy-mm-dd")
            End If
        End If
    Next i

    f1 = sc + nCol: f2 = f1 - 1
    Do While wsT.Cells(hr + 1, f2 + 1).HasFormula: f2 = f2 + 1: Loop
    If f2 >= f1 Then
        ReDim fml(f1 To f2)
        For c = f1 To f2: fml(c) = wsT.Cells(hr + 1, c).FormulaR1C1: Next c
    End If
    oldLast = wsT.Cells(wsT.Rows.Count, sc).End(xlUp).Row
    If oldLast < hr + n Then oldLast = hr + n
    wsT.Range(wsT.Cells(hr + 1, sc), wsT.Cells(oldLast, sc + nCol - 1)).ClearContents
    If dc > 0 Then wsT.Range(wsT.Cells(hr + 1, sc + dc - 1), wsT.Cells(hr + n, sc + dc - 1)).NumberFormat = "@"
    wsT.Cells(hr + 1, sc).Resize(n, nCol).Value = data
    If f2 >= f1 Then
        For c = f1 To f2
            fl = wsT.Cells(wsT.Rows.Count, c).End(xlUp).Row
            If fl < hr + 1 Then fl = hr
            If fl < hr + n Then wsT.Range(wsT.Cells(fl + 1, c), wsT.Cells(hr + n, c)).FormulaR1C1 = fml(c)
        Next c
    End If
    stampMsg = PutStamp(wsT, hr, sc, hasDate, sDate, hasTime, sTime, stamp)

    Application.Calculation = calcMode
    Application.ScreenUpdating = True
    Application.DisplayAlerts = True
    wsT.Activate
    MsgBox "AR import done: " & n & " rows; " & skipped & " blank rows skipped." & vbLf & stampMsg, vbInformation
    Exit Sub
EH:
    If Not wbS Is Nothing Then wbS.Close False
    Application.Calculation = calcMode
    Application.ScreenUpdating = True
    Application.DisplayAlerts = True
    MsgBox "Error: " & Err.Description, vbCritical
End Sub