public class Rawenv.Service : Object {
    public string name { get; set; default = ""; }
    public int port { get; set; default = 0; }
    public string version { get; set; default = ""; }
    public int pid { get; set; default = 0; }
    public string cpu { get; set; default = ""; }
    public string mem { get; set; default = ""; }
    public string uptime { get; set; default = ""; }
    public string status { get; set; default = "stopped"; }
    public string icon { get; set; default = ""; }
}
