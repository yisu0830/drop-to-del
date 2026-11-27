using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.Diagnostics;
using System.Collections.Generic;
using Microsoft.VisualBasic.FileIO;

class DropToDel : Form {
    ListView list = new ListView();
    Label status = new Label();
    Button recycle = new Button();
    int skipped;
    [STAThread] static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new DropToDel());
    }
    DropToDel() {
        Text = "Drop to Del · 桌面碎纸机";
        Size = new Size(720, 390);
        MinimumSize = new Size(460, 240);
        TopMost = true;
        AllowDrop = true;
        list.Dock = DockStyle.Fill;
        list.View = View.Details;
        list.CheckBoxes = true;
        list.FullRowSelect = true;
        list.Columns.Add("清理项", 150);
        list.Columns.Add("文件位置（双击定位）", 525);
        list.DoubleClick += delegate {
            if (list.SelectedItems.Count > 0)
                Process.Start("explorer.exe", "/select,\"" + list.SelectedItems[0].SubItems[1].Text + "\"");
        };
        status.Dock = DockStyle.Top;
        status.Height = 36;
        status.TextAlign = ContentAlignment.MiddleLeft;
        status.Text = "把文件或项目文件夹拖到这里，然后勾选要清理的项目。";
        recycle.Text = "将勾选项移到回收站";
        recycle.Dock = DockStyle.Bottom;
        recycle.Height = 38;
        recycle.Click += Recycle;
        Controls.Add(list); Controls.Add(status); Controls.Add(recycle);
        DragEnter += delegate(object sender, DragEventArgs e) {
            e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        };
        DragDrop += delegate(object sender, DragEventArgs e) {
            string[] paths = e.Data.GetData(DataFormats.FileDrop) as string[];
            if (paths == null) return;
            list.Items.Clear(); skipped = 0;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            list.BeginUpdate();
            try { foreach (string path in paths) Scan(path, seen); }
            finally { list.EndUpdate(); }
            status.Text = String.Format("找到 {0} 项，跳过 {1} 项。请核对路径后勾选。", list.Items.Count, skipped);
        };
    }
    static bool Safe(string path) {
        string root = Path.GetPathRoot(path);
        if (root.Length < 3 || new DriveInfo(root).DriveType != DriveType.Fixed) return false;
        foreach (string blocked in new string[] { Environment.SystemDirectory, Environment.GetFolderPath(Environment.SpecialFolder.Windows), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Path.Combine(root, "$Recycle.Bin"), Path.Combine(root, "System Volume Information") }) {
            if (blocked.Length > 0 && (path.Equals(blocked, StringComparison.OrdinalIgnoreCase) || path.StartsWith(blocked + "\\", StringComparison.OrdinalIgnoreCase))) return false;
        }
        for (string part = path; part != null; part = Path.GetDirectoryName(part)) {
            if ((File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0) return false;
        }
        return !path.Equals(root, StringComparison.OrdinalIgnoreCase);
    }
    void Scan(string start, HashSet<string> seen) {
        var pending = new Stack<string>(); pending.Push(start);
        while (pending.Count > 0) {
            string path = pending.Pop();
            try {
                if (!seen.Add(path)) continue;
                if (!Safe(path)) { skipped++; continue; }
                bool dir = Directory.Exists(path);
                string name = Path.GetFileName(path).ToLowerInvariant();
                string parent = Path.GetDirectoryName(path);
                string folder = Path.GetFileName(parent);
                string kind = null;
                if (dir) {
                    if (name == ".git" || name == ".svn" || name == ".hg") continue;
                    if (name == "node_modules") {
                        if (File.Exists(Path.Combine(parent, "package.json"))) kind = "依赖（需重新安装）";
                    } else foreach (string child in Directory.GetFileSystemEntries(path)) pending.Push(child);
                } else if (name == ".ds_store" || name == "thumbs.db") kind = "显示缓存";
                else if (folder == "_work" && Array.IndexOf(new string[]{"最新检查.json","motion-qa.json","最新导出.log","结尾检查.png"}, name) >= 0) kind = "过程检查记录";
                else if (folder == ".thumbnails" && name.StartsWith("v5_") && name.Contains("_index.html_") && name.EndsWith(".jpg") && File.Exists(Path.Combine(Path.GetDirectoryName(parent), "hyperframes.json"))) kind = "预览缩略图";
                else if (System.Text.RegularExpressions.Regex.IsMatch(name, @"(demo|screenshot|检查|自测|截图).*\.(png|jpe?g|webp)$")) kind = "待确认图片";
                else if (path == start) kind = "拖入的文件";
                if (kind != null) {
                    var row = new ListViewItem(new string[]{kind, path});
                    row.Tag = File.GetLastWriteTimeUtc(path); list.Items.Add(row);
                }
            } catch (Exception) { skipped++; }
        }
    }
    void Recycle(object sender, EventArgs e) {
        var rows = new List<ListViewItem>();
        foreach (ListViewItem row in list.CheckedItems) rows.Add(row);
        if (rows.Count == 0 || MessageBox.Show(this, "将选中的 " + rows.Count + " 项移到回收站？", Text, MessageBoxButtons.OKCancel) != DialogResult.OK) return;
        int done = 0;
        foreach (var row in rows) {
            string path = row.SubItems[1].Text;
            try {
                if (!Safe(path) || (DateTime)row.Tag != File.GetLastWriteTimeUtc(path)) throw new IOException("文件已变化，请重新扫描。");
                if (Directory.Exists(path)) FileSystem.DeleteDirectory(path, UIOption.AllDialogs, RecycleOption.SendToRecycleBin, UICancelOption.ThrowException);
                else FileSystem.DeleteFile(path, UIOption.AllDialogs, RecycleOption.SendToRecycleBin, UICancelOption.ThrowException);
                list.Items.Remove(row); done++;
            } catch (OperationCanceledException) { break; }
            catch (Exception ex) { MessageBox.Show(this, path + Environment.NewLine + ex.Message, Text); break; }
        }
        status.Text = "已处理 " + done + " 项。";
    }
}
