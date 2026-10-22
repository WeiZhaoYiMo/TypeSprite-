using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("打字桌宠")]
[assembly: AssemblyDescription("全局打字计数桌宠")]
[assembly: AssemblyCompany("TypingPet")]
[assembly: AssemblyProduct("打字桌宠")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length > 0 && string.Equals(args[0], "--self-test", StringComparison.OrdinalIgnoreCase))
            {
                if (ReadResource("TypingPet.ps1").Length < 100 || ReadResource("pet.png").Length < 100)
                    throw new InvalidOperationException("Embedded resource validation failed.");
                return 0;
            }

            string appRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TypingPet", "app");
            string assetsRoot = Path.Combine(appRoot, "assets");
            Directory.CreateDirectory(assetsRoot);

            string scriptPath = Path.Combine(appRoot, "TypingPet.ps1");
            string imagePath = Path.Combine(assetsRoot, "pet.png");
            ExtractUtf8Script("TypingPet.ps1", scriptPath);
            ExtractBinary("pet.png", imagePath);

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershellPath)) powershellPath = "powershell.exe";

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershellPath;
            startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + scriptPath + "\"";
            startInfo.WorkingDirectory = appRoot;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;
            startInfo.EnvironmentVariables["TYPING_PET_ROOT"] = appRoot;
            Process.Start(startInfo);
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "打字桌宠启动失败：\r\n\r\n" + exception.Message,
                "打字桌宠",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static void ExtractUtf8Script(string resourceName, string destination)
    {
        byte[] content = ReadResource(resourceName);
        bool hasUtf8Bom = content.Length >= 3 && content[0] == 0xEF && content[1] == 0xBB && content[2] == 0xBF;
        if (hasUtf8Bom)
        {
            File.WriteAllBytes(destination, content);
            return;
        }

        byte[] output = new byte[content.Length + 3];
        output[0] = 0xEF;
        output[1] = 0xBB;
        output[2] = 0xBF;
        Buffer.BlockCopy(content, 0, output, 3, content.Length);
        File.WriteAllBytes(destination, output);
    }

    private static void ExtractBinary(string resourceName, string destination)
    {
        File.WriteAllBytes(destination, ReadResource(resourceName));
    }

    private static byte[] ReadResource(string resourceName)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream stream = assembly.GetManifestResourceStream(resourceName))
        {
            if (stream == null) throw new InvalidOperationException("缺少内置资源：" + resourceName);
            using (MemoryStream memory = new MemoryStream())
            {
                stream.CopyTo(memory);
                return memory.ToArray();
            }
        }
    }
}

