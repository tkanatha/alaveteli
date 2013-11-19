This document has notes on switching your Alaveteli theme to use
the Rails asset pipeline.

Firstly, add the following to your `lib/alavetelitheme.rb`, in
order to add your theme's `assets` directory to
`config.assets.path`:

    # Prepend the asset directories in this theme to the asset path:
    ['stylesheets', 'images', 'javascripts'].each do |asset_type|
        theme_asset_path = File.join(File.dirname(__FILE__),
                                     '..',
                                     'assets',
                                     asset_type)
        Rails.application.config.assets.paths.unshift theme_asset_path
    end

In the root of your theme, create these directories:

    assets
     \ images
     \ stylesheets
     \ javascripts

i.e. `assets` is at the same level as `lib` and `locale-theme`.

Move any image files from `public/images` to `assets/images`.
Now change any references to those images with a literal `<img>`
tag to use `image_tag` instead.  For example, instead of:

    <img src="/images/helpmeinvestigate.png" alt="" class="rss">

... you should have:

    image_tag('helpmeinvestigate.png', :alt => "", :class => "rss")

You should similarly move your stylesheets into
`assets/stylesheets`.  If a stylesheet refers to images, you
should rename the `.css` file to `.css.scss`, and change `url`
to the sass-rails `image-url` helper.  e.g. instead of:

    background-image: url(../images/mysociety.png);

... you should have:

    background-image: image-url('mysociety.png');

If your only stylesheet is called `custom.css`, as in the
example theme, the only change you need to make is to make sure
that the contents of
`lib/views/general/_stylesheet_includes.html.erb` are:

    <%- if @render_to_file %>
      <style>
      </style>
    <%- else %>
      <%= stylesheet_link_tag "application" %>
    <% end %>

Any custom Javascript should similarly be moved to
`assets/javascripts` in your theme directory.

You should be left with nothing in the `public` directory after
making these changes, except possibly custom error pages.
