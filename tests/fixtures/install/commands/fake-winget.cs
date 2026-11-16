using System;
using System.IO;
class FakeWinget {
    static string Report(string state) {
        string source = Path.Combine(state, "report-source");
        return File.Exists(source) ? File.ReadAllText(source).Trim() : Path.Combine(state, "results");
    }
    static void Snapshot(string state, string operation) {
        string path = Path.Combine(state, operation + "-snapshot");
        if (File.Exists(path)) File.Copy(Report(state), File.ReadAllText(path).Trim(), true);
    }
    static int Main(string[] args) {
        string state = Environment.GetEnvironmentVariable("DOTFILES_TEST_PACKAGE_STATE");
        if (String.IsNullOrEmpty(state)) return 91;
        File.AppendAllText(Path.Combine(state, "commands"), String.Join(" ", args) + "\n");
        if (String.Equals(Path.GetFileName(Environment.GetCommandLineArgs()[0]), "vswhere.exe", StringComparison.OrdinalIgnoreCase)) {
            string probeExit = Path.Combine(state, "probe-exit");
            return File.Exists(probeExit) ? Int32.Parse(File.ReadAllText(probeExit).Trim()) : 0;
        }
        int id = Array.IndexOf(args, "--id");
        if (args.Length == 0 || id < 0 || id + 1 >= args.Length) return 91;
        string package = args[id + 1];
        string marker = Path.Combine(state, "installed-" + package);
        if (args[0] == "list") {
            Snapshot(state, "probe");
            string code = Path.Combine(state, "probe-exit");
            if (File.Exists(code)) return Int32.Parse(File.ReadAllText(code).Trim());
            // Empty successful inventory represents a nonmatching package.
            if (File.Exists(marker)) Console.WriteLine(package + " 1.0");
            return 0;
        }
        if (args[0] != "install") return 91;
        File.AppendAllText(Path.Combine(state, "installs"), package + "\n");
        Snapshot(state, "install");
        string identity = Path.Combine(state, "report-id");
        string reportId = File.Exists(identity) ? File.ReadAllText(identity).Trim() : package;
        string report = File.ReadAllText(Report(state));
        if (!report.Contains(reportId + "|running|")) return 92;
        string corruptStage = Path.Combine(state, "corrupt-stage");
        if (File.Exists(corruptStage)) File.WriteAllText(File.ReadAllText(corruptStage).Trim(), "# dotfiles|stage-result|99\nkey|value\n");
        string installExit = Path.Combine(state, "install-exit");
        if (File.Exists(installExit)) return Int32.Parse(File.ReadAllText(installExit).Trim());
        if (File.Exists(Path.Combine(state, "fail-" + package))) return 23;
        if (!File.Exists(Path.Combine(state, "skip-evidence"))) File.WriteAllText(marker, "");
        return 0;
    }
}
