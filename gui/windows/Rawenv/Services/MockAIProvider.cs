using Rawenv.Interfaces;

namespace Rawenv.Services;

public class MockAIProvider : IAIProvider
{
    public string AutonomyLevel { get; set; } = "suggest-only";

    public Task<string> SendAsync(string prompt)
    {
        return Task.FromResult($"[Mock AI] Received: {prompt}. I suggest optimizing your configuration.");
    }
}
