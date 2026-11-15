using System;
using System.IO;
class FakeWinget {
    static int Main(string[] args) {
        string state = Environment.GetEnvironmentVariable("DOTFILES_TEST_PACKAGE_STATE");
        if (String.IsNullOrEmpty(state)) return 91;
        File.AppendAllText(Path.Combine(state, "commands"), String.Join(" ", args) + "\n");
        int id = Array.IndexOf(args, "--id");
        if (args.Length == 0 || id < 0 || id + 1 >= args.Length) return 91;
        string package = args[id + 1];
        string marker = Path.Combine(state, "installed-" + package);
        if (args[0] == "list") {
            string code = Path.Combine(state, "probe-exit");
            if (File.Exists(code)) return Int32.Parse(File.ReadAllText(code).Trim());
            // Empty successful inventory represents a nonmatching package.
            if (File.Exists(marker)) Console.WriteLine(package + " 1.0");
            return 0;
        }
        if (args[0] != "install") return 91;
        File.AppendAllText(Path.Combine(state, "installs"), package + "\n");
        string report = File.ReadAllText(Path.Combine(state, "results"));
        if (!report.Contains(package + "|running|")) return 92;
        if (File.Exists(Path.Combine(state, "fail-" + package))) return 23;
        File.WriteAllText(marker, "");
        return 0;
    }
}
