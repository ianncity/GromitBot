namespace GromitBot.Agent.Nav;

public static class Pathfinder
{
    public static IReadOnlyList<int> FindPath(NavMesh mesh, int startNodeId, int goalNodeId)
    {
        if (startNodeId == goalNodeId)
        {
            return [startNodeId];
        }

        Dictionary<int, List<int>> graph = [];
        foreach (NavEdge edge in mesh.Edges)
        {
            if (!graph.TryGetValue(edge.From, out List<int>? fromAdj))
            {
                fromAdj = [];
                graph[edge.From] = fromAdj;
            }

            if (!graph.TryGetValue(edge.To, out List<int>? toAdj))
            {
                toAdj = [];
                graph[edge.To] = toAdj;
            }

            fromAdj.Add(edge.To);
            toAdj.Add(edge.From);
        }

        Queue<int> queue = new();
        HashSet<int> visited = [];
        Dictionary<int, int> prev = [];

        queue.Enqueue(startNodeId);
        visited.Add(startNodeId);

        while (queue.Count > 0)
        {
            int current = queue.Dequeue();
            if (!graph.TryGetValue(current, out List<int>? neighbors))
            {
                continue;
            }

            foreach (int next in neighbors)
            {
                if (!visited.Add(next))
                {
                    continue;
                }

                prev[next] = current;
                if (next == goalNodeId)
                {
                    return BuildPath(prev, startNodeId, goalNodeId);
                }

                queue.Enqueue(next);
            }
        }

        return [];
    }

    private static IReadOnlyList<int> BuildPath(Dictionary<int, int> prev, int startNodeId, int goalNodeId)
    {
        List<int> path = [goalNodeId];
        int current = goalNodeId;

        while (prev.TryGetValue(current, out int parent))
        {
            path.Add(parent);
            current = parent;
            if (current == startNodeId)
            {
                break;
            }
        }

        path.Reverse();
        return path;
    }
}