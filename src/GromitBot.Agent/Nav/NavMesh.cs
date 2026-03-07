namespace GromitBot.Agent.Nav;

public sealed class NavMesh
{
    public string Name { get; set; } = "unknown";

    public List<NavNode> Nodes { get; set; } = [];

    public List<NavEdge> Edges { get; set; } = [];
}