using Rawenv.Interfaces;

namespace Rawenv.Services;

public class NavigationService : INavigationService
{
    private readonly Stack<string> _history = new();
    public event Action<string>? Navigated;

    public void NavigateTo(string destination)
    {
        _history.Push(destination);
        Navigated?.Invoke(destination);
    }

    public void GoBack()
    {
        if (_history.Count > 1)
        {
            _history.Pop();
            Navigated?.Invoke(_history.Peek());
        }
    }
}
