using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;

namespace AiyueTransfer.App;

public partial class MainWindow : Window
{
    public MainWindow() { InitializeComponent(); DataContext = new NearbyDevicesViewModel(); }
}

public sealed class NearbyDeviceCard(string alias, string deviceType)
{
    public string Alias { get; } = alias;
    public string DeviceType { get; } = deviceType;
    public ICommand SendCommand { get; } = new SimpleCommand(() => { });
}

public sealed class NearbyDevicesViewModel
{
    public ObservableCollection<NearbyDeviceCard> Devices { get; } = [];
    public string EmptyText => Devices.Count == 0 ? "暂未发现设备，点击“刷新”重试" : string.Empty;
    public ICommand RefreshCommand { get; }
    public NearbyDevicesViewModel() => RefreshCommand = new SimpleCommand(() => { });
}

public sealed class SimpleCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}
