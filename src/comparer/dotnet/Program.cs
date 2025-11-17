using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using OpenXmlPowerTools;

namespace Etir.Comparer;

public static class Entry
{
    [UnmanagedCallersOnly(EntryPoint = "docx_compare")]
    public static int DocxCompare(
        nint beforePathUtf8,
        nint afterPathUtf8,
        nint reviewOutPathUtf8,
        nint authorUtf8,
        nint dateIsoUtf8)
    {
        try
        {
            var beforePath = RequireUtf8(beforePathUtf8);
            var afterPath = RequireUtf8(afterPathUtf8);
            var outPath = RequireUtf8(reviewOutPathUtf8);
            var author = RequireUtf8(authorUtf8);
            var dateString = OptionalUtf8(dateIsoUtf8);

            var before = new WmlDocument(beforePath);
            var after = new WmlDocument(afterPath);

            var settings = new WmlComparerSettings
            {
                AuthorForRevisions = author,
            };

            if (!string.IsNullOrWhiteSpace(dateString) &&
                DateTimeOffset.TryParse(dateString, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto))
            {
                settings.DateTimeForRevisions = dto.UtcDateTime.ToString("o", CultureInfo.InvariantCulture);
            }

            var compared = WmlComparer.Compare(before, after, settings);
            EnsureDirectory(outPath);
            compared.SaveAs(outPath);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"docx_compare exception: {ex}");
            return 1;
        }
    }

    private static string RequireUtf8(nint ptr)
    {
        return Marshal.PtrToStringUTF8(ptr) ?? throw new ArgumentNullException(nameof(ptr));
    }

    private static string? OptionalUtf8(nint ptr)
    {
        return ptr == 0 ? null : Marshal.PtrToStringUTF8(ptr);
    }

    private static void EnsureDirectory(string outputPath)
    {
        var directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }
    }
}
