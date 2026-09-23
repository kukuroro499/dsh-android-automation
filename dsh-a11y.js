"auto";
auto.waitFor();

var DIR  = "/sdcard/dsh-shared/";
var F_HB = DIR + "a11y.hb";
var MAP = {
    "com.tencent.mobileqq": DIR + "a11y-qq.txt",
    "com.tencent.mm":       DIR + "a11y-wx.txt"
};

function w(p, s) { try { files.write(p, String(s)); } catch (e) {} }
w(DIR + "a11y-boot.txt", "v7 boot " + new Date().toString());

function collect() {
    var rows = [];
    var list = null;
    try { list = textMatches("[\\s\\S]+").find(); } catch (e) { list = null; }
    var n = 0;
    if (list) { try { n = list.size(); } catch (e) { n = (list.length || 0); } }
    for (var i = 0; i < n; i++) {
        var nd = null;
        try { nd = list.get(i); } catch (e) { continue; }
        var t = null;
        try { t = nd.text(); } catch (e) {}
        if (!t) continue;
        t = String(t);
        if (t.replace(/\s/g, "").length === 0) continue;
        var top = 0;
        try { top = nd.bounds().top; } catch (e) {}
        rows.push([top, t]);
    }
    rows.sort(function (a, b) { return a[0] - b[0]; });
    var out = [];
    for (var j = 0; j < rows.length; j++) out.push("y=" + rows[j][0] + " " + rows[j][1]);
    return out.join("\n");
}

var last = {};
var busy = false;

function tick() {
    if (busy) return;
    busy = true;
    try {
        w(F_HB, String(Date.now()));
        var pkg = "";
        try { pkg = currentPackage(); } catch (e) {}
        var f = MAP[pkg];
        if (f) {
            var s = collect();
            // v7 关键修复：空结果绝不覆盖（前台切换瞬间会读到空树，会把文件清空）
            if (s && s.length > 0 && s !== last[pkg]) {
                last[pkg] = s;
                w(f, s);
            }
        }
    } catch (e) {
        w(DIR + "a11y-err.txt", String(e));
    }
    busy = false;
}

setInterval(tick, 800);
toast("dsh-a11y v7");
