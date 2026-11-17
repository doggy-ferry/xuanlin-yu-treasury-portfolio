// Independently designed and implemented by the author on synthetic data.
// Not an export of any employer's workbook.
// Business rules, data design and acceptance testing by the author; AI assisted coding and documentation.
let
    RootFolder = "<ROOT_PATH>\AR",
    Files = Folder.Files(RootFolder),
    Candidates = Table.SelectRows(Files, each
        Text.StartsWith([Name], "AR Balance Report", Comparer.OrdinalIgnoreCase)
        and not Text.StartsWith([Name], "~$") and ([Attributes]?[Hidden]? <> true)),
    Latest = if Table.RowCount(Candidates)=0 then error "No AR file found"
             else Table.First(Table.Sort(Candidates, {{"Date modified", Order.Descending}})),
    Xml = Xml.Document(Latest[Content], 65001),
    WorkbookNode = Table.SelectRows(Xml, each [Name] = "Workbook"){0}[Table],
    WorksheetNode = Table.SelectRows(WorkbookNode, each [Name] = "Worksheet"){0}[Table],
    TableNode = Table.SelectRows(WorksheetNode, each [Name] = "Table"){0}[Table],
    Rows = Table.SelectRows(TableNode, each [Name] = "Row")[Table],
    CellToValue = (cell as any) as any =>
        let t = if Value.Is(cell, type table) then cell else #table({},{}),
            d = Table.SelectRows(t, each [Name] = "Data")
        in if Table.RowCount(d)=0 then null else d{0}[Value],
    RowToList = (r as any) as list =>
        let t = if Value.Is(r, type table) then r else #table({},{}),
            cells = Table.SelectRows(t, each [Name] = "Cell"),
            recs = Table.ToRecords(cells),
            built = List.Accumulate(recs, {}, (state, current) =>
                let idxRaw = try Record.Field(current, "Index") otherwise null,
                    idx = if idxRaw = null then List.Count(state)+1 else Number.From(idxRaw),
                    padded = List.Combine({state, List.Repeat({null}, Number.Max(0, idx-List.Count(state)-1))}),
                    value = CellToValue(Record.Field(current, "Table"))
                in List.Combine({padded,{value}}))
        in built,
    Lists = List.Transform(Rows, each RowToList(_)),
    Width = List.Max(List.Transform(Lists, each List.Count(_))),
    Padded = List.Transform(Lists, each List.Combine({_, List.Repeat({null}, Width-List.Count(_))})),
    Matrix = Table.FromRows(Padded),
    SkipToHeader = Table.Skip(Matrix, each not List.Contains(Record.FieldValues(_), "Due Date")),
    Headers = Table.PromoteHeaders(SkipToHeader, [PromoteAllScalars=true]),
    DataRows = Table.SelectRows(Headers, each [Accounting Period] <> null and [Accounting Period] <> ""),
    AmountColumns = List.Select(Table.ColumnNames(DataRows), each
        (Text.Contains(_, "Amount") or Text.Contains(_, "Transaction Currency") or Text.Contains(_, "Functional Currency"))
        and not Text.EndsWith(_, "Currency")),
    TypedAmounts = Table.TransformColumnTypes(DataRows, List.Transform(AmountColumns, each {_, type number}), "en-US"),
    DueDateClean = Table.TransformColumns(TypedAmounts, {{"Due Date", each try Date.From(Text.Start(Text.From(_),10)) otherwise _, type any}})
in
    DueDateClean