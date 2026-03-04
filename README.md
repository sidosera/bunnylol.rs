<p align="center">
  <img src="bunny.png" alt="Bunnylol" width="128" height="128">
</p>

<h3 align="center">Lolabunny</h3>

Lightweight fully local command router that let you navigate apps, tools, and internal resources directly from your browser address bar. Type `gh` foo to jump to GitHub issues, `ticket 2500` to open that ticket, or `wiki How to ...` to search your internal wiki. It just issues HTTP redirects, no browser extension, no cloud, no account. 


## Nah, why not just use bookmarks?

I tried options like native browser bookmarks and tools like Yubnub, but nothing really fit my workflow and after years of using a [similar system](https://www.quora.com/What-is-Facebooks-bunnylol) internally at Facebook, I couldn’t imagine working without it. So I built Lolabunny, inspired by [bunnylol.rs](https://github.com/facebook/bunnylol.rs) by Aaron Lichtman and Joe Previte, with a focus on simplicity and zero-friction setup.

## 📦 How to install

Lolabunny is basically a small local server binary that handles searches from your browser. It doesn't dictate where you keep the binary or how you run it. 
For convenience, it comes a desktop widget so you can get set up quickly with minimal hassle.

See [releases](https://github.com/sidosera/lolabunny.app/releases) for installation options.

## Extensions

You can extend Lolabunny with Lua. For example, the standard extension package [sidosera/lolacore](https://github.com/sidosera/homebrew-lolacore) is just a handful of Lua files.

You can clone `sidosera/lolacore` and scratch your own extensions bundle e.g. `me/my-workflow` which you can then brew install.

```sh
brew tap me/my-workflow
brew install my-workflow
```

## 🔖 Setup (the only config)

If macOS blocks the app, remove the quarantine attribute:

```sh
xattr -cr /Applications/Lolabunny.app
```

Enable "Launch at Login", then set your browser search engine to:

```text
http://localhost:8085/?cmd=%s
```

E.g. for [Chrome](https://support.google.com/chrome/answer/95426).

## License

MIT

