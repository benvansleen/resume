 <img alt="PNG of `main.pdf`" src="./media/main-fdf0362.png">


## Development setup
1. Make sure you're in a `nix develop` environment (or `direnv allow`, in this case)
2. Run `nix run .#watch`, and resume will rebuild after each change to `*.tex`
3. When finished, commit changes. This will fail, as `*.pdf` & `*.png` should refresh & get added to git staged index
4. Commit again & push
