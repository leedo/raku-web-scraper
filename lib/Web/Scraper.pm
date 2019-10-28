use v6;

class Web::Scraper {
  use URI;
  use HTTP::UserAgent;
  use Web::Scraper::Rule;
  use LibXML;
  use LibXML::XPath::Context;
  use CSS::Selector::To::XPath;

  has Web::Scraper::Rule %.rules;

  sub process ($css, $name is copy, $value) is export {
    my $multiple = $name ~~ s/ '[]' $//;
    my $xpath = CSS::Selector::To::XPath.new.selector-to-xpath(:$css);
    my $rule = Web::Scraper::Rule.new(
      :selector($xpath),
      :value($value),
      :multiple(?$multiple)
    );

    $*scraper.add-rule($name, $rule);
  }

  sub scraper(&code) is export {
    my $*scraper = Web::Scraper.new;
    &code.();
    return $*scraper;
  }

  method add-rule (Str $name, Web::Scraper::Rule $rule) {
    %!rules{$name} = $rule;
  }

  multi method scrape (URI $uri) {
    my $ua = HTTP::UserAgent.new;
    my $res = $ua.get($uri.Str);

    if $res.is-success {
      return $.extract($res.content);
    }

    die $res.status-line;
  }

  multi method scrape (Str $content) {
    return $.extract($content);
  }

  multi method extract (Str $content) {
    my $parser = LibXML.new;
    my $doc = $parser.parse(
      :string($content),
      :html,
      :recover,
      :suppress-errors,
      :!pedantic-parser
      :!blanks,
      :expand-entities,
      :!network,
    );
    $.extract($doc);
  }

  multi method extract ($node) {
    return hash %!rules.kv.map: -> $name, $rule {
      $name => $.extract-rule($rule, $node);
    };
  }

  method extract-rule (Web::Scraper::Rule $rule, $node) {
    return $rule.extract($node.findnodes($rule.selector));
  }
}
