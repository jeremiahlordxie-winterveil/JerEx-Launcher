namespace JerEx.JEL;

static class Program
{
    private static Mutex? _singleInstance;
    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main(string[] args)
    {
        using var mutex = new Mutex(true, "Local\\JerEx.JEL", out var isFirstInstance);
        _singleInstance = mutex;
        if (!isFirstInstance)
        {
            MessageBox.Show("JEL is already running.", "JEL", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var diagnosticOnly = args.Any(x => x.Equals("--diagnostic", StringComparison.OrdinalIgnoreCase));
        var closeWhenDone = diagnosticOnly && args.Any(x => x.Equals("--headless", StringComparison.OrdinalIgnoreCase));
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(diagnosticOnly, closeWhenDone));
    }
}
