# WINDOWS

## Client

This all occurs within `rubyCards/client/`

### Required tools

`iexpress`
Enigma Virtual Box
`ldd` or some other tool for discovering the needed dll files for a binary

### Process

Pull down the git repository

Comment out `rubocop` and `ruby-lsp` in the Gemfile, they're not Windows friendly gems and you don't need them to run the client. Then `bundle clean` and `bundle install`.

Using `iexpress`, open the .SED project file and choose to modify it. You should just need to change the path of the `client.bat` file that gets packed. Please don't commit the change if you choose to save the modifications.

Put your ruby version in scripts/Ruby (this is tested with 3.0.7). It needs to be pretty much everything, ruby needs to be able to run totally independently within the virtual system we're making

The gosu library needs a bunch of dll files that you can see if you use `ldd` (if you have mingw) or supposedly something like `dumpbin` and search for the DLL files. You can put these files anywhere but keep them all in one place for ease of access

Run Enigma Virtual Box and open the project file in `scripts/`. The actual paths that it will try to pull these files from is specific to my machine, you will need to essentially build your own EVB project with the shape that is indicated by the project you opened. Make sure to change the input (The .exe you created with `iexpress`) and output file paths. You can remove any files in the `scripts/` directory (but obviously not `Ruby/`) and then put all your dll files that you collected into `%System Folder%/`. Please don't commit any of these changes if you choose to save the project file.

You should be able to process and run the produced executable.