<div align="center">
<img 
  src="https://github.com/user-attachments/assets/50862f8a-7826-4d07-9ecd-5281216e5982" 
  width="2000" 
  style="border-radius: 30px;" 
/>
</div>


### Burrito

A lightweight macOS menu bar app for optimizing images. Drag and drop files onto the popover to compress them as **PNG** or **WebP**, no extra steps.

https://github.com/user-attachments/assets/de94b2fd-c711-46d1-b790-6626954f07af

## Download

**Option 1** — Grab the latest `.dmg` from [GitHub Releases](https://github.com/SwishHQ/burrito/releases).

**Option 2** — Install via the command line:

```bash
curl -L -o Burrito.dmg \
  https://github.com/SwishHQ/burrito/releases/latest/download/Burrito.dmg
open Burrito.dmg
```

Then drag **Burrito.app** into your Applications folder.

> Requires **macOS 15.6** or later.


## Contributing

Contributions are welcome! Here's how to get started:

1. **Fork** the repository.
2. **Clone** your fork:
   ```bash
   git clone https://github.com/<your-username>/Burrito.git
   ```
3. Open `Burrito.xcodeproj` in Xcode (15+).
4. Create a new branch for your change:
   ```bash
   git checkout -b my-feature
   ```
5. Make your changes and verify the build succeeds (⌘B).
6. **Commit** with a clear message and **push** your branch:
   ```bash
   git push origin my-feature
   ```
7. Open a **Pull Request** against `main`.

### Guidelines

- Keep PRs focused — one feature or fix per PR.
- Match the existing code style (SwiftUI, no storyboards).
- Test on macOS 15.6+ before submitting.

## License

MIT License



Built with 💚 by Swish Design 
