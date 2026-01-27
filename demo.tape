# pwt Demo - Power Worktrees
# Run: vhs demo.tape

Output demo.gif
Set FontSize 14
Set Width 800
Set Height 450
Set Theme "Catppuccin Mocha"
Set Padding 15
Set TypingSpeed 50ms

# Use local pwt directly
Env PATH "/Users/jonasporto/llm-tools/pwt/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
Env PWT_LIB "/Users/jonasporto/llm-tools/pwt/lib/pwt"

Hide
Type "cd /Users/jonasporto/llm-tools/pwt"
Enter
Sleep 500ms
Show

# Show version
Type "pwt --version"
Enter
Sleep 1s

# List worktrees
Type "pwt list"
Enter
Sleep 2s

# Tree view
Type "pwt tree"
Enter
Sleep 2s

# Show help
Type "pwt help | head -20"
Enter
Sleep 2s

# Doctor check
Type "pwt doctor"
Enter
Sleep 2s

# Done
Type "# github.com/jonasporto/pwt"
Enter
Sleep 1500ms
