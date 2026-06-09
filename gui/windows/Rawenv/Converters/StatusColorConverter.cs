using Microsoft.UI;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;

namespace Rawenv.Converters;

public class StatusColorConverter : IValueConverter
{
    private static readonly SolidColorBrush Running = new(ColorHelper.FromArgb(255, 0x34, 0xd3, 0x99));
    private static readonly SolidColorBrush Stopped = new(ColorHelper.FromArgb(255, 0xf8, 0x71, 0x71));
    private static readonly SolidColorBrush Warning = new(ColorHelper.FromArgb(255, 0xfb, 0xbf, 0x24));

    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value?.ToString() switch
        {
            "running" => Running,
            "stopped" => Stopped,
            _ => Warning
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotImplementedException();
}
