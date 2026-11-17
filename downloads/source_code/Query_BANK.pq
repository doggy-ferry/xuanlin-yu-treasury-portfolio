// Independently designed and implemented by the author on synthetic data.
// Not an export of any employer's workbook.
// Business rules, data design and acceptance testing by the author; AI assisted coding and documentation.
let
    RootFolder = "<ROOT_PATH>\BANK",
    Files = Table.SelectRows(Folder.Files(RootFolder), each [Attributes]?[Hidden]? <> true),
    TransformFile = (content as binary, fileName as text) as table =>
        let
            Raw = Csv.Document(content, [Delimiter=",", Encoding=932, QuoteStyle=QuoteStyle.Csv]),
            FormalRows = Table.SelectRows(Raw, each [Column1] = "2"),
            Account = try Text.From(Raw{0}[Column13]) otherwise null,
            WithAccount = Table.AddColumn(FormalRows, "Account Number", each Account, type text),
            WithSource = Table.AddColumn(WithAccount, "Source File", each fileName, type text)
        in WithSource,
    Applied = Table.AddColumn(Files, "Data", each TransformFile([Content], [Name])),
    Combined = Table.Combine(Applied[Data]),
    Reordered = Table.ReorderColumns(Combined, List.Combine({{"Account Number","Source File"}, List.RemoveItems(Table.ColumnNames(Combined), {"Account Number","Source File"})})),
    Typed = Table.TransformColumnTypes(Reordered, {{"Account Number", type text}, {"Source File", type text}})
in
    Typed