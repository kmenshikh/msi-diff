# Direct P/Invoke access to msi.dll.
#
# The COM automation interface works, but every field read costs a late-bound IDispatch
# round-trip, which makes large packages take tens of seconds to read. The native API is
# roughly an order of magnitude faster and returns the same data.

$ErrorActionPreference = 'Stop'

if (-not ('MsiDiff.PackageReader' -as [type])) {

    $source = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace MsiDiff
{
    public sealed class MsiTable
    {
        public string Name;
        public string[] Columns;
        public Hashtable ColumnTypes;
        public Hashtable ColumnKinds;
        public string[] PrimaryKeys;
        public Hashtable[] Rows;
        public string Error;
    }

    public static class PackageReader
    {
        private const uint ERROR_SUCCESS = 0;
        private const uint ERROR_MORE_DATA = 234;
        private const uint ERROR_NO_MORE_ITEMS = 259;

        // MSIHANDLE is a 32-bit value even in 64-bit processes.
        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiOpenDatabaseW(string databasePath, IntPtr persist, out uint database);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiGetLastErrorRecord();

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiFormatRecordW(uint install, uint record, StringBuilder result, ref int size);

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiDatabaseOpenViewW(uint database, string query, out uint view);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiViewExecute(uint view, uint record);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiViewFetch(uint view, out uint record);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiViewClose(uint view);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiViewGetColumnInfo(uint view, int columnInfo, out uint record);

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiDatabaseGetPrimaryKeysW(uint database, string tableName, out uint record);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiCloseHandle(uint handle);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern int MsiRecordGetFieldCount(uint record);

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiRecordGetStringW(uint record, int field, StringBuilder value, ref int size);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern int MsiRecordGetInteger(uint record, int field);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern int MsiRecordDataSize(uint record, int field);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern bool MsiRecordIsNull(uint record, int field);

        [DllImport("msi.dll", ExactSpelling = true)]
        private static extern uint MsiRecordReadStream(uint record, int field, byte[] buffer, ref int size);

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiGetSummaryInformationW(uint database, string databasePath, uint updateCount, out uint summaryInfo);

        [DllImport("msi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint MsiSummaryInfoGetPropertyW(uint summaryInfo, int property, out uint dataType,
            out int intValue, ref System.Runtime.InteropServices.ComTypes.FILETIME fileTime, StringBuilder value, ref int size);

        private static string Quote(string identifier)
        {
            return "`" + identifier + "`";
        }

        private static string GetString(uint record, int field)
        {
            int size = 256;
            StringBuilder buffer = new StringBuilder(size);
            uint result = MsiRecordGetStringW(record, field, buffer, ref size);
            if (result == ERROR_MORE_DATA)
            {
                size++;
                buffer = new StringBuilder(size);
                result = MsiRecordGetStringW(record, field, buffer, ref size);
            }
            if (result != ERROR_SUCCESS) { return string.Empty; }
            return buffer.ToString();
        }

        private static string FormatWin32(uint result)
        {
            return new System.ComponentModel.Win32Exception((int)result).Message;
        }

        // MsiGetLastErrorRecord / MsiFormatRecord carry the template Windows Installer
        // filled in, including any nested system error. Empty when nothing was recorded.
        private static string FormatLastMsiError()
        {
            uint record = MsiGetLastErrorRecord();
            if (record == 0) { return string.Empty; }
            try
            {
                int size = 1024;
                StringBuilder buffer = new StringBuilder(size);
                uint code = MsiFormatRecordW(0, record, buffer, ref size);
                if (code == ERROR_MORE_DATA)
                {
                    size++;
                    buffer = new StringBuilder(size);
                    code = MsiFormatRecordW(0, record, buffer, ref size);
                }
                if (code != ERROR_SUCCESS) { return string.Empty; }
                return buffer.ToString().Trim();
            }
            finally
            {
                MsiCloseHandle(record);
            }
        }

        public static uint OpenDatabase(string path)
        {
            uint database;
            uint result = MsiOpenDatabaseW(path, IntPtr.Zero, out database); // MSIDBOPEN_READONLY
            if (result != ERROR_SUCCESS)
            {
                string text = FormatWin32(result);
                string detail = FormatLastMsiError();
                if (!string.IsNullOrEmpty(detail) &&
                    !detail.Equals(text, StringComparison.OrdinalIgnoreCase))
                {
                    text = detail + " (" + text + ", error " + result + ")";
                }
                else
                {
                    text = text + " (error " + result + ")";
                }
                throw new InvalidOperationException("Cannot open '" + path + "': " + text);
            }
            return database;
        }

        public static void CloseDatabase(uint database)
        {
            if (database != 0) { MsiCloseHandle(database); }
        }

        public static string[] GetTableNames(uint database)
        {
            List<string> names = new List<string>();
            uint view;
            uint result = MsiDatabaseOpenViewW(database, "SELECT `Name` FROM `_Tables`", out view);
            if (result != ERROR_SUCCESS) { return names.ToArray(); }
            try
            {
                if (MsiViewExecute(view, 0) != ERROR_SUCCESS) { return names.ToArray(); }
                while (true)
                {
                    uint record;
                    if (MsiViewFetch(view, out record) != ERROR_SUCCESS || record == 0) { break; }
                    names.Add(GetString(record, 1));
                    MsiCloseHandle(record);
                }
            }
            finally
            {
                MsiViewClose(view);
                MsiCloseHandle(view);
            }
            names.Sort(StringComparer.Ordinal);
            return names.ToArray();
        }

        private static string[] GetPrimaryKeys(uint database, string table)
        {
            List<string> keys = new List<string>();
            uint record;
            if (MsiDatabaseGetPrimaryKeysW(database, table, out record) != ERROR_SUCCESS || record == 0)
            {
                return keys.ToArray();
            }
            try
            {
                int count = MsiRecordGetFieldCount(record);
                for (int i = 1; i <= count; i++) { keys.Add(GetString(record, i)); }
            }
            finally
            {
                MsiCloseHandle(record);
            }
            return keys.ToArray();
        }

        private static string GetColumnKind(string type)
        {
            if (string.IsNullOrEmpty(type)) { return "string"; }
            switch (type[0])
            {
                case 'v': case 'V': case 'o': case 'O': return "stream";
                case 'i': case 'I': case 'j': case 'J': return "int";
                default: return "string";
            }
        }

        private static string DescribeStream(uint record, int field, bool hashStreams)
        {
            int size = MsiRecordDataSize(record, field);
            if (size <= 0) { return "[stream: empty]"; }
            if (!hashStreams) { return "[stream: " + size + " bytes]"; }

            using (SHA256 sha = SHA256.Create())
            {
                byte[] buffer = new byte[65536];
                int remaining = size;
                while (remaining > 0)
                {
                    int take = Math.Min(buffer.Length, remaining);
                    int got = take;
                    if (MsiRecordReadStream(record, field, buffer, ref got) != ERROR_SUCCESS || got <= 0) { break; }
                    sha.TransformBlock(buffer, 0, got, null, 0);
                    remaining -= got;
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);

                StringBuilder hex = new StringBuilder(32);
                for (int i = 0; i < 8; i++) { hex.Append(sha.Hash[i].ToString("x2")); }
                return "[stream: " + size + " bytes; sha256=" + hex + "]";
            }
        }

        public static MsiTable ReadTable(uint database, string table, bool hashStreams)
        {
            MsiTable result = new MsiTable();
            result.Name = table;
            result.Columns = new string[0];
            result.ColumnTypes = new Hashtable(StringComparer.OrdinalIgnoreCase);
            result.ColumnKinds = new Hashtable(StringComparer.OrdinalIgnoreCase);
            result.PrimaryKeys = new string[0];
            result.Rows = new Hashtable[0];

            uint view;
            uint code = MsiDatabaseOpenViewW(database, "SELECT * FROM " + Quote(table), out view);
            if (code != ERROR_SUCCESS)
            {
                result.Error = "MsiDatabaseOpenView failed with code " + code;
                return result;
            }

            try
            {
                code = MsiViewExecute(view, 0);
                if (code != ERROR_SUCCESS)
                {
                    result.Error = "MsiViewExecute failed with code " + code;
                    return result;
                }

                uint nameRecord, typeRecord;
                MsiViewGetColumnInfo(view, 0, out nameRecord); // MSICOLINFO_NAMES
                MsiViewGetColumnInfo(view, 1, out typeRecord); // MSICOLINFO_TYPES

                int fieldCount = MsiRecordGetFieldCount(nameRecord);
                string[] columns = new string[fieldCount];
                string[] kinds = new string[fieldCount];
                for (int i = 0; i < fieldCount; i++)
                {
                    string name = GetString(nameRecord, i + 1);
                    string type = GetString(typeRecord, i + 1);
                    columns[i] = name;
                    kinds[i] = GetColumnKind(type);
                    result.ColumnTypes[name] = type;
                    result.ColumnKinds[name] = kinds[i];
                }
                MsiCloseHandle(nameRecord);
                MsiCloseHandle(typeRecord);
                result.Columns = columns;
                result.PrimaryKeys = GetPrimaryKeys(database, table);

                List<Hashtable> rows = new List<Hashtable>();
                while (true)
                {
                    uint record;
                    if (MsiViewFetch(view, out record) != ERROR_SUCCESS || record == 0) { break; }
                    try
                    {
                        // Case-insensitive to match PowerShell hashtable semantics.
                        Hashtable row = new Hashtable(fieldCount, StringComparer.OrdinalIgnoreCase);
                        for (int i = 0; i < fieldCount; i++)
                        {
                            int field = i + 1;
                            switch (kinds[i])
                            {
                                case "int":
                                {
                                    int value = MsiRecordGetInteger(record, field);
                                    row[columns[i]] = (value == int.MinValue && MsiRecordIsNull(record, field))
                                        ? null : (object)value;
                                    break;
                                }
                                case "stream":
                                    row[columns[i]] = DescribeStream(record, field, hashStreams);
                                    break;
                                default:
                                {
                                    string value = GetString(record, field);
                                    row[columns[i]] = (value.Length == 0 && MsiRecordIsNull(record, field))
                                        ? null : (object)value;
                                    break;
                                }
                            }
                        }
                        rows.Add(row);
                    }
                    finally
                    {
                        MsiCloseHandle(record);
                    }
                }
                result.Rows = rows.ToArray();
            }
            finally
            {
                MsiViewClose(view);
                MsiCloseHandle(view);
            }
            return result;
        }

        // Returns property id -> value (string, int or DateTime). Naming and decoding stay in PowerShell.
        public static Hashtable ReadSummary(string path)
        {
            Hashtable values = new Hashtable();
            uint summary;
            if (MsiGetSummaryInformationW(0, path, 0, out summary) != ERROR_SUCCESS) { return values; }

            try
            {
                int[] properties = new int[] { 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 18, 19 };
                foreach (int property in properties)
                {
                    uint dataType;
                    int intValue;
                    System.Runtime.InteropServices.ComTypes.FILETIME fileTime =
                        new System.Runtime.InteropServices.ComTypes.FILETIME();
                    int size = 256;
                    StringBuilder buffer = new StringBuilder(size);

                    uint code = MsiSummaryInfoGetPropertyW(summary, property, out dataType, out intValue,
                        ref fileTime, buffer, ref size);
                    if (code == ERROR_MORE_DATA)
                    {
                        size++;
                        buffer = new StringBuilder(size);
                        code = MsiSummaryInfoGetPropertyW(summary, property, out dataType, out intValue,
                            ref fileTime, buffer, ref size);
                    }
                    if (code != ERROR_SUCCESS) { continue; }

                    switch (dataType)
                    {
                        case 2:  // VT_I2
                        case 3:  // VT_I4
                            values[property] = intValue;
                            break;
                        case 30: // VT_LPSTR
                            values[property] = buffer.ToString();
                            break;
                        case 64: // VT_FILETIME
                        {
                            long ticks = ((long)fileTime.dwHighDateTime << 32) | ((uint)fileTime.dwLowDateTime);
                            if (ticks > 0)
                            {
                                values[property] = DateTime.FromFileTime(ticks);
                            }
                            break;
                        }
                    }
                }
            }
            finally
            {
                MsiCloseHandle(summary);
            }
            return values;
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp
}
