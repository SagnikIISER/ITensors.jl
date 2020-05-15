include("settings.jl")

makedocs(sitename = sitename;
         modules = modules,
         pages = pages,
         format = Documenter.HTML(prettyurls = false),
         doctest = true,
         checkdocs = :none)

deploydocs(repo = "github.com/ITensor/ITensors.jl.git")
