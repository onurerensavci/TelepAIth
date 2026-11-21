using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using Microsoft.Win32;

namespace TelepAIth;

/// <summary>
/// Windows 11 görünümü: yuvarlak köşeli gölgeli menüler, anahtar düğmeler, kartlar; açık/koyu temaya göre renkler.
/// Stiller bir kez yüklenir, renkler DynamicResource olduğu için tema değişince canlı güncellenir.
/// </summary>
internal static class Theme
{
    public const string Icons = "Segoe Fluent Icons, Segoe MDL2 Assets";
    public const string Font = "Segoe UI Variable Text, Segoe UI, Segoe UI Emoji";
    public const string DisplayFont = "Segoe UI Variable Display, Segoe UI";

    public static bool IsDark
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch { return false; }
        }
    }

    private static bool _loaded;

    public static void Apply()
    {
        var res = Application.Current.Resources;
        if (!_loaded)
        {
            _loaded = true;
            res.MergedDictionaries.Add((ResourceDictionary)XamlReader.Parse(Styles));
            SystemEvents.UserPreferenceChanged += (_, e) =>
            {
                if (e.Category == UserPreferenceCategory.General)
                    Application.Current.Dispatcher.BeginInvoke(SetPalette);
            };
        }
        SetPalette();
    }

    private static void SetPalette()
    {
        var dark = IsDark;
        var res = Application.Current.Resources;
        void Set(string key, string light, string darkHex)
        {
            var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark ? darkHex : light));
            b.Freeze();
            res[key] = b;
        }
        Set("Bg", "#F3F3F3", "#202020");
        Set("Side", "#EBEBEB", "#1C1C1C");
        Set("Card", "#FBFBFB", "#2B2B2B");
        Set("CardBorder", "#E5E5E5", "#383838");
        Set("Text", "#1B1B1B", "#FFFFFF");
        Set("SubText", "#5F5F5F", "#A8A8A8");
        Set("Hover", "#0A000000", "#0FFFFFFF");
        Set("Selected", "#12000000", "#17FFFFFF");
        Set("Control", "#FFFFFF", "#2F2F2F");
        Set("ControlHover", "#F5F5F5", "#363636");
        Set("MenuBg", "#F9F9F9", "#2C2C2C");
        Set("MenuBorder", "#E3E3E3", "#404040");
        Set("Scroll", "#8A8A8A", "#8F8F8F");
        Set("Accent", "#7C5CFF", "#9B85FF");
        Set("AccentText", "#FFFFFF", "#1B1037");
        Set("Good", "#0F7B3F", "#6CCB8F");
        Set("Warn", "#B8590B", "#F2A65A");
        Set("Shadow", "#000000", "#000000");
    }

    // MARK: Pencereler

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    /// <summary>Pencereyi temaya bağlar: arka plan, yazı rengi, yazı tipi, koyu başlık çubuğu, Windows 11 yuvarlak köşeler.</summary>
    public static void Style(Window w)
    {
        w.SetResourceReference(Control.BackgroundProperty, "Bg");
        w.SetResourceReference(Control.ForegroundProperty, "Text");
        w.FontFamily = new FontFamily(Font);
        w.FontSize = 13;
        w.SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(w).Handle;
            try
            {
                var dark = IsDark ? 1 : 0;
                DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));       // koyu başlık çubuğu
                var round = 2;
                DwmSetWindowAttribute(hwnd, 33, ref round, sizeof(int));      // yuvarlak köşeler (Windows 11)
            }
            catch { }
        };
    }

    private static class Control
    {
        public static readonly DependencyProperty BackgroundProperty = System.Windows.Controls.Control.BackgroundProperty;
        public static readonly DependencyProperty ForegroundProperty = System.Windows.Controls.Control.ForegroundProperty;
    }

    // MARK: Stiller

    private const string Styles = """
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <!-- Menü kutusu: gölge + yuvarlak köşeli zemin -->
  <ControlTemplate x:Key="MenuBox" TargetType="ContentControl">
    <Grid Margin="10,6,10,14">
      <Border CornerRadius="8" Background="{DynamicResource MenuBg}" Opacity="0.55">
        <Border.Effect>
          <DropShadowEffect BlurRadius="16" ShadowDepth="4" Direction="270" Opacity="0.28" Color="Black"/>
        </Border.Effect>
      </Border>
      <Border CornerRadius="8" Background="{DynamicResource MenuBg}" BorderBrush="{DynamicResource MenuBorder}" BorderThickness="1" Padding="0,4">
        <ContentPresenter/>
      </Border>
    </Grid>
  </ControlTemplate>

  <Style TargetType="ContextMenu">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="UseLayoutRounding" Value="True"/>
    <Setter Property="HasDropShadow" Value="False"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI, Segoe UI Emoji"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="MinWidth" Value="220"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ContextMenu">
          <ContentControl Template="{StaticResource MenuBox}" MinWidth="{TemplateBinding MinWidth}">
            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
          </ContentControl>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="{x:Static MenuItem.SeparatorStyleKey}" TargetType="Separator">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Separator">
          <Border Height="1" Margin="0,4" Background="{DynamicResource MenuBorder}"/>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="MenuItem">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="MenuItem">
          <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Margin="4,1" Padding="10,0" MinHeight="32" SnapsToDevicePixels="True">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="28"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <ContentPresenter x:Name="IconBox" Grid.Column="0" ContentSource="Icon" VerticalAlignment="Center" HorizontalAlignment="Left"/>
              <TextBlock x:Name="Check" Grid.Column="0" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13"
                         VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource Accent}" Visibility="Collapsed"/>
              <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="False" VerticalAlignment="Center" Margin="0,6,18,6"/>
              <TextBlock x:Name="Arrow" Grid.Column="2" Text="&#xE76C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10"
                         VerticalAlignment="Center" Foreground="{DynamicResource SubText}" Visibility="Collapsed"/>
              <Popup x:Name="PART_Popup" Placement="Right" HorizontalOffset="-4" VerticalOffset="-11" AllowsTransparency="True" Focusable="False"
                     PopupAnimation="Fade" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}">
                <ContentControl Template="{StaticResource MenuBox}" MinWidth="200" Foreground="{DynamicResource Text}"
                                FontFamily="Segoe UI Variable Text, Segoe UI, Segoe UI Emoji" FontSize="13">
                  <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                </ContentControl>
              </Popup>
            </Grid>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
              <Setter TargetName="IconBox" Property="Visibility" Value="Hidden"/>
            </Trigger>
            <Trigger Property="HasItems" Value="True">
              <Setter TargetName="Arrow" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="IsHighlighted" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
            </Trigger>
            <Trigger Property="IsSubmenuOpen" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Hover}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Foreground" Value="{DynamicResource SubText}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Düğmeler -->
  <Style TargetType="Button">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Background" Value="{DynamicResource Control}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
    <Setter Property="Padding" Value="14,6"/>
    <Setter Property="MinHeight" Value="32"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Grid>
            <Border x:Name="B" CornerRadius="4" BorderThickness="1" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"/>
            <Border x:Name="Over" CornerRadius="4" Background="{DynamicResource Hover}" Visibility="Hidden"/>
            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="False"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Over" Property="Visibility" Value="Visible"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.8"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background" Value="{DynamicResource Accent}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="Foreground" Value="{DynamicResource AccentText}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>

  <!-- Anahtar düğme (Windows 11 ayarlarındaki gibi) -->
  <Style x:Key="Switch" TargetType="CheckBox">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Focusable" Value="False"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Grid Width="40" Height="20" Background="Transparent">
            <Border x:Name="Track" CornerRadius="10" BorderThickness="1" BorderBrush="{DynamicResource SubText}" Background="Transparent"/>
            <Ellipse x:Name="Thumb" Width="12" Height="12" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="4,0,0,0" Fill="{DynamicResource SubText}"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Thumb" Property="Width" Value="14"/>
              <Setter TargetName="Thumb" Property="Height" Value="14"/>
              <Setter TargetName="Thumb" Property="Margin" Value="3,0,0,0"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Track" Property="Background" Value="{DynamicResource Accent}"/>
              <Setter TargetName="Track" Property="BorderBrush" Value="{DynamicResource Accent}"/>
              <Setter TargetName="Thumb" Property="Fill" Value="{DynamicResource AccentText}"/>
              <Setter TargetName="Thumb" Property="Margin" Value="24,0,0,0"/>
            </Trigger>
            <MultiTrigger>
              <MultiTrigger.Conditions>
                <Condition Property="IsChecked" Value="True"/>
                <Condition Property="IsMouseOver" Value="True"/>
              </MultiTrigger.Conditions>
              <Setter TargetName="Thumb" Property="Margin" Value="23,0,0,0"/>
            </MultiTrigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Açılır liste -->
  <Style TargetType="ComboBoxItem">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Grid Margin="4,1">
            <Border x:Name="B" CornerRadius="4" Background="Transparent"/>
            <Border x:Name="Pill" Width="3" Height="16" CornerRadius="1.5" HorizontalAlignment="Left" Background="{DynamicResource Accent}" Visibility="Hidden"/>
            <ContentPresenter Margin="12,7,12,7" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="B" Property="Background" Value="{DynamicResource Selected}"/>
              <Setter TargetName="Pill" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBox">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="MinWidth" Value="170"/>
    <Setter Property="Height" Value="32"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template>
                <ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="B" CornerRadius="4" BorderThickness="1" BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource Control}"/>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource ControlHover}"/></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter IsHitTestVisible="False" Margin="12,0,32,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                              Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
            <TextBlock IsHitTestVisible="False" Text="&#xE70D;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10"
                       HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="{DynamicResource SubText}"/>
            <Popup x:Name="PART_Popup" Placement="Bottom" HorizontalOffset="-10" VerticalOffset="-2" AllowsTransparency="True" Focusable="False"
                   PopupAnimation="Fade" IsOpen="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}">
              <ContentControl Template="{StaticResource MenuBox}" Foreground="{DynamicResource Text}"
                              MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                              FontFamily="Segoe UI Variable Text, Segoe UI, Segoe UI Emoji" FontSize="13">
                <ScrollViewer MaxHeight="320" VerticalScrollBarVisibility="Auto">
                  <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                </ScrollViewer>
              </ContentControl>
            </Popup>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Ayarlar kenar çubuğu -->
  <Style x:Key="Nav" TargetType="ListBox">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBox">
          <StackPanel IsItemsHost="True"/>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="NavItem" TargetType="ListBoxItem">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Grid Margin="0,2">
            <Border x:Name="B" CornerRadius="4" Background="Transparent"/>
            <Border x:Name="Pill" Width="3" Height="16" CornerRadius="1.5" HorizontalAlignment="Left" Background="{DynamicResource Accent}" Visibility="Hidden"/>
            <ContentPresenter Margin="14,9,12,9" VerticalAlignment="Center"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="B" Property="Background" Value="{DynamicResource Selected}"/>
              <Setter TargetName="Pill" Property="Visibility" Value="Visible"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- İnce kaydırma çubuğu -->
  <Style TargetType="ScrollBar">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Width" Value="10"/>
    <Setter Property="MinWidth" Value="10"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="Thumb">
                    <Border CornerRadius="3" Margin="3,2" Background="{DynamicResource Scroll}" Opacity="0.7"/>
                  </ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
          <ControlTemplate.Triggers>
            <Trigger Property="Orientation" Value="Horizontal">
              <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Orientation" Value="Horizontal">
        <Setter Property="Width" Value="Auto"/>
        <Setter Property="MinWidth" Value="0"/>
        <Setter Property="Height" Value="10"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style x:Key="Mono" TargetType="TextBox">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Text}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="FontFamily" Value="Cascadia Mono, Consolas"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="IsReadOnly" Value="True"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
  </Style>
</ResourceDictionary>
""";
}
