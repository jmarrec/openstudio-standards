require 'diffy'
require 'cgi'
require 'securerandom'
require 'pathname'

ROOT_DIR = Pathname.new(__dir__)
STANDARDS_DIR = ROOT_DIR / "lib/openstudio-standards/standards"

def get_side_by_side_html_diff(a, b, context: 3, pane_height: "500px")
  diff = Diffy::Diff.new(a, b, context: context, :include_diff_info => false)

  left_lines  = []
  right_lines = []
  left_num  = 1
  right_num = 1

  diff.each do |line|
    text = CGI.escapeHTML(line[1..-1])

    case line
    when /^\+/
      right_lines << "<div><span class='ln'>#{right_num}</span><span class='added'>#{text}</span></div>"
      left_lines  << "<div><span class='ln'>&nbsp;</span></div>"
      right_num += 1
    when /^-/
      left_lines  << "<div><span class='ln'>#{left_num}</span><span class='removed'>#{text}</span></div>"
      right_lines << "<div><span class='ln'>&nbsp;</span></div>"
      left_num += 1
    else
      left_lines  << "<div><span class='ln'>#{left_num}</span>#{text}</div>"
      right_lines << "<div><span class='ln'>#{right_num}</span>#{text}</div>"
      left_num  += 1
      right_num += 1
    end
  end

  uid = SecureRandom.hex(4) # 8-char unique ID

  html = <<~HTML
    <style>
      .diffy-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        grid-gap: 20px;
        font-family: monospace;
        white-space: pre;
      }
      .diffy-col {
        height: #{pane_height};
        overflow: auto;
        padding: 4px;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: #fafafa;
      }
      .diffy-col > div { padding: 1px 4px; }
      .added   { background: #eaffea; color: #080; }
      .removed { background: #ffecec; color: #900; }
      .ln {
        display: inline-block;
        width: 3em;
        color: #888;
        text-align: right;
        margin-right: 0.5em;
      }
    </style>
    <div class="diffy-grid">
      <div class="diffy-col" id="diff-left-#{uid}">
        #{left_lines.join}
      </div>
      <div class="diffy-col" id="diff-right-#{uid}">
        #{right_lines.join}
      </div>
    </div>
    <script>
      (function() {
        const left  = document.getElementById("diff-left-#{uid}");
        const right = document.getElementById("diff-right-#{uid}");
        let syncing = false;

        function syncScroll(source, target) {
          if (syncing) return;
          syncing = true;
          target.scrollTop = source.scrollTop;
          syncing = false;
        }

        left.addEventListener("scroll", () => syncScroll(left, right));
        right.addEventListener("scroll", () => syncScroll(right, left));
      })();
    </script>
  HTML

  html
end

def format_location(method)
  loc = method.source_location
  rel_path = Pathname.new(loc[0]).relative_path_from(STANDARDS_DIR)
  "#{rel_path}#L#{loc[1]}"
end

def open_in_gvim(method)
  loc = method.source_location
  file = Pathname.new(loc[0]).realpath
  line = loc[1]
  system("gvim +#{line} #{file}")
end

def diff_method(lhs_class, rhs_class, method_name, add_buttons: true)
  lhs_method = lhs_class.instance_method(method_name.to_sym)
  rhs_method = rhs_class.instance_method(method_name.to_sym)
  if lhs_method.owner == rhs_method.owner
    puts "#{lhs_class} and #{rhs_class} use the same owner: #{lhs_method.owner}\n"

    short_link = format_location(lhs_method)
    link = "https://github.com/jmarrec/openstudio-standards/blob/179D/lib/openstudio-standards/standards/#{short_link}"
    html = "<a href='#{link}'>#{short_link}</a>\n"
    IRuby.display html, mime: 'text/html'
    #{format_location(lhs_method)}\n"
    if add_buttons
      result = IRuby.form do
        button(key=:open_gvim, color: :blue)
        cancel
      end
      if result && result[:open_gvim]
        open_in_gvim(lhs_method)
      end

    end
    return
  end

  puts "--- #{lhs_class}"
  puts "+++ #{rhs_class}"

  diff = Diffy::Diff.new(
    "Owner: #{lhs_method.owner}\n\n#{format_location(lhs_method)}\n",
    "Owner: #{rhs_method.owner}\n\n#{format_location(rhs_method)}\n",
  )
  puts diff

  html = get_side_by_side_html_diff(
    lhs_method.source,
    rhs_method.source
  )

  IRuby.display html, mime: 'text/html'

  return unless add_buttons
  result = IRuby.form do
    button(key=:open_gvim_lhs, color: :blue)
    button(key=:open_gvim_rhs, color: :green)
    cancel
  end
  if result
    if result[:open_gvim_lhs]
      open_in_gvim(lhs_method)
    end
    if result[:open_gvim_rhs]
      open_in_gvim(rhs_method)
    end
  end

end
