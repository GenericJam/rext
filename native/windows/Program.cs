// rext — Windows native render backend (WinForms).
//
// The opt-in *native* backend for Windows: real Win32 controls (genuine native
// feel), the platform font (Segoe UI). Implements the rext render protocol (see
// rext/guides/render_protocol.md) over the socket transport — same wire format
// as the SwiftUI (macOS native) and Compose (baseline) renderers.
//
// Connect: REXT_PORT (bridge port), REXT_WINDOW (which window to draw).
// Build/run on Windows:  dotnet run   (env: REXT_PORT / REXT_WINDOW)

using System.Buffers.Binary;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace RextRenderer;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        int port = int.TryParse(Environment.GetEnvironmentVariable("REXT_PORT"), out var p) ? p : 8137;
        string target = Environment.GetEnvironmentVariable("REXT_WINDOW") ?? "main";

        ApplicationConfiguration.Initialize();
        var form = new RenderForm(target);
        new Bridge(port, target, form).Start();
        Application.Run(form);
    }
}

// ── The window: rebuilds native controls from each render frame ──────────────

internal sealed class RenderForm : Form
{
    public Action<string, string>? SendEvent;

    public RenderForm(string title)
    {
        Text = title.Length > 0 ? char.ToUpper(title[0]) + title[1..] : title;
        ClientSize = new Size(460, 320);
        BackColor = Color.FromArgb(30, 30, 40);
    }

    public void ApplyTree(JsonElement tree)
    {
        SuspendLayout();
        Controls.Clear();
        var root = BuildControl(tree);
        root.Dock = DockStyle.Fill;
        Controls.Add(root);
        ResumeLayout();
    }

    private Control BuildControl(JsonElement node)
    {
        string type = node.TryGetProperty("type", out var t) ? t.GetString() ?? "box" : "box";
        var props = node.TryGetProperty("props", out var pr) ? pr : default;
        var children = node.TryGetProperty("children", out var ch) ? ch : default;

        switch (type)
        {
            case "column":
            case "row":
            {
                var panel = new FlowLayoutPanel
                {
                    FlowDirection = type == "column" ? FlowDirection.TopDown : FlowDirection.LeftToRight,
                    Dock = DockStyle.Fill,
                    WrapContents = false,
                    Padding = new Padding(Num(props, "padding") ?? 0),
                };
                if (HexColor(Str(props, "background")) is { } bg)
                {
                    panel.BackColor = bg;
                }

                int gap = Num(props, "gap") ?? 8;
                if (children.ValueKind == JsonValueKind.Array)
                {
                    foreach (var c in children.EnumerateArray())
                    {
                        var ctl = BuildControl(c);
                        ctl.Margin = type == "column" ? new Padding(0, 0, 0, gap) : new Padding(0, 0, gap, 0);
                        panel.Controls.Add(ctl);
                    }
                }

                return panel;
            }
            case "text":
            {
                var lbl = new Label
                {
                    Text = Str(props, "text") ?? "",
                    AutoSize = true,
                    Font = new Font("Segoe UI", Num(props, "size") ?? 12),
                };
                if (HexColor(Str(props, "color")) is { } fc)
                {
                    lbl.ForeColor = fc;
                }

                return lbl;
            }
            case "button":
            {
                var btn = new Button
                {
                    Text = Str(props, "label") ?? "",
                    AutoSize = true,
                    FlatStyle = FlatStyle.System, // native Win32 button
                };
                if (Str(props, "on_click") is { } tag)
                {
                    btn.Click += (_, _) => SendEvent?.Invoke("click", tag);
                }

                return btn;
            }
            default:
            {
                var box = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, Dock = DockStyle.Fill };
                if (children.ValueKind == JsonValueKind.Array)
                {
                    foreach (var c in children.EnumerateArray())
                    {
                        box.Controls.Add(BuildControl(c));
                    }
                }

                return box;
            }
        }
    }

    private static string? Str(JsonElement props, string key) =>
        props.ValueKind == JsonValueKind.Object && props.TryGetProperty(key, out var v) &&
        v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;

    private static int? Num(JsonElement props, string key) =>
        props.ValueKind == JsonValueKind.Object && props.TryGetProperty(key, out var v) &&
        v.ValueKind == JsonValueKind.Number
            ? v.GetInt32()
            : null;

    private static Color? HexColor(string? s)
    {
        if (s is null || s.Length != 7 || s[0] != '#')
        {
            return null;
        }

        return Color.FromArgb(
            Convert.ToInt32(s.Substring(1, 2), 16),
            Convert.ToInt32(s.Substring(3, 2), 16),
            Convert.ToInt32(s.Substring(5, 2), 16));
    }
}

// ── Bridge: socket transport (4-byte length-framed JSON) ─────────────────────

internal sealed class Bridge
{
    private readonly int _port;
    private readonly string _target;
    private readonly RenderForm _form;
    private NetworkStream? _stream;

    public Bridge(int port, string target, RenderForm form)
    {
        _port = port;
        _target = target;
        _form = form;
    }

    public void Start()
    {
        _form.SendEvent = SendEvent;
        new Thread(Loop) { IsBackground = true }.Start();
    }

    private void Loop()
    {
        try
        {
            using var client = new TcpClient("127.0.0.1", _port);
            _stream = client.GetStream();
            Send("{\"t\":\"hello\",\"renderer\":\"winforms\"}");

            while (true)
            {
                int len = BinaryPrimitives.ReadInt32BigEndian(ReadExactly(4)); // matches Erlang {:packet, 4}
                var body = ReadExactly(len);
                using var doc = JsonDocument.Parse(body);
                var obj = doc.RootElement;
                // One renderer draws one window; ignore frames for others.
                if (obj.GetProperty("t").GetString() == "render" &&
                    obj.GetProperty("window").GetString() == _target)
                {
                    string treeJson = obj.GetProperty("tree").GetRawText();
                    _form.BeginInvoke(() =>
                    {
                        using var td = JsonDocument.Parse(treeJson);
                        _form.ApplyTree(td.RootElement);
                    });
                }
            }
        }
        catch
        {
            // Connection ended (BEAM gone) — quit so we don't orphan the renderer.
            Environment.Exit(0);
        }
    }

    private void SendEvent(string ev, string tag) =>
        Send($"{{\"t\":\"event\",\"window\":\"{_target}\",\"event\":\"{ev}\",\"tag\":\"{tag}\"}}");

    private void Send(string json)
    {
        if (_stream is null)
        {
            return;
        }

        var body = Encoding.UTF8.GetBytes(json);
        var header = new byte[4];
        BinaryPrimitives.WriteInt32BigEndian(header, body.Length);
        lock (_stream)
        {
            _stream.Write(header);
            _stream.Write(body);
            _stream.Flush();
        }
    }

    private byte[] ReadExactly(int n)
    {
        var buf = new byte[n];
        int off = 0;
        while (off < n)
        {
            int r = _stream!.Read(buf, off, n - off);
            if (r <= 0)
            {
                throw new IOException("connection closed");
            }

            off += r;
        }

        return buf;
    }
}
