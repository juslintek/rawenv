public class Rawenv.Project : Object {
    public string name { get; set; default = ""; }
    public string path { get; set; default = ""; }
    public string deps { get; set; default = ""; }
    public string[] stack { get; set; default = {}; }
}
