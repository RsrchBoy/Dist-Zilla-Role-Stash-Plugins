package Dist::Zilla::Role::Stash::Plugins;
# ABSTRACT: A Stash that stores arguments for plugins

use strict;
use warnings;
use Moose::Role;
with qw(
	Dist::Zilla::Role::DynamicConfig
	Dist::Zilla::Role::Stash
);

# we could define a 'plugged' module attribute and create a generic
# method like sub expand_package { $_[0]->plugged_module->expand_package($_[1]) }
# but this is a Role (not an actual stash) and is that really useful?

requires 'expand_package';

=attr argument_separator

A regular expression that will capture
the package name in C<$1> and
the attribute name in C<$2>.

Defaults to C<< ^(.+?)\W+(\w+)$ >>
which means the package variable and the attribute
will be separated by non-word characters
(which assumes the attributes will be
only word characters/valid perl identifiers).

You will need to set this attribute in your stash
if you need to assign to an attribute in a package that contains
non-word characters.
This is an example (taken from the tests in F<t/ini-sep>).

	# dist.ini
	[%Example]
	argument_separator = ^([^|]+)\|([^|]+)$
	-PlugName|Attr::Name = oops
	+Mod::Name|!goo-ber = nuts

=cut

has argument_separator => (
    is       => 'ro',
    isa      => 'Str',
	# "Module::Name:variable" "-Plugin/variable"
    default  => '^(.+?)\W+(\w+)$'
);

=attr _config

Contains the dynamic options.

Inherited from L<Dist::Zilla::Role::DynamicConfig>.

Rather than accessing this directly,
consider L</get_stashed_config> or L</merge_stashed_config>.

=cut

# _config inherited

=method get_stashed_config

Return a hashref of the config arguments for the plugin
determined by C<< ref($plugin) >>.

This is a slice of the I<_config> attribute
appropriate for the plugin passed to the method.

	# with a stash of:
	# _config => {
	#   'APlug:attr1'   => 'value1',
	#   'APlug:second'  => '2nd',
	#   'OtherPlug:attr => '0'
	# }

	# from inside Dist::Zilla::Plugin::APlug

	if( my $stash = $self->zilla->stash_named('%Example') ){
		my $stashed = $stash->get_stashed_config($self);
	}

	# $stashed => {
	#   'attr1'   => 'value1',
	#   'second'  => '2nd'
	# }

=cut

sub get_stashed_config {
	my ($self, $plugin) = @_;

	# use ref() rather than $plugin->plugin_name() because we want to match
	# the full package name as returned by expand_package() below
	# rather than '@Bundle/ShortPluginName'
	my $name = ref($plugin);

	my $config = $self->_config;
	my $stashed = {};
	my $splitter = qr/${\ $self->argument_separator }/;

	while( my ($key, $value) = each %$config ){
		my ($plug, $attr) = ($key =~ $splitter);

		unless($plug && $attr){
			warn("[${\ ref($self) }] '$key' did not match $splitter.  " .
				"Do you need a more specific 'argument_separator'?");
			next;
		}

		my $pack = $self->expand_package($plug);

		$stashed->{$attr} = $value
			if $pack eq $name;
	}
	return $stashed;
}

=method merge_stashed_config

	$stash->merge_stashed_config($plugin, \%opts);

Get the stashed config (see L</get_stashed_config>),
then attempt to merge it into the plugin.

This require the plugin's attributes to be writable (C<'rw'>).

It will attempt to push onto array references and
concatenate onto existing strings (joined by a space).
It will overwrite any other types.

Possible options:

=for :list
* I<stashed>
A hashref like that returned from L</get_stashed_config>.
If not present, L</get_stashed_config> will be called.

=cut

sub merge_stashed_config {
	my ($self, $plugin, $opts) = @_;
	my $stashed = $opts->{stashed} || $self->get_stashed_config($plugin);

	while( my ($key, $value) = each %$stashed ){
		# call attribute writer (attribute must be 'rw'!)
		my $attr = $plugin->meta->find_attribute_by_name($key);
		my $type = $attr->type_constraint;
		my $previous = $plugin->$key;
		if( $previous ){
			if( UNIVERSAL::isa($previous, 'ARRAY') ){
				push(@$previous, $value);
			}
			elsif( $type->name eq 'Str' ){
				# TODO: pass in string for joining
				$plugin->$key(join(' ', $previous, $value));
			}
			#elsif( $type->name eq 'Bool' )
			else {
				$plugin->$key($value);
			}
		}
		else {
			$value = [$value]
				if $type->name =~ /^arrayref/i;

			$plugin->$key($value);
		}
	}
}

=method separate_local_config

Removes any hash keys that are only word characters
(valid perl identifiers (including L</argument_separator>))
because the dynamic keys intended for other plugins will all
contain non-word characters.

Overwrite this if necessary.

=cut

sub separate_local_config {
	my ($self, $config) = @_;
	# keys for other plugins should include non-word characters
	# (like "-Plugin::Name:variable"), so any keys that are only
	# word characters (valid identifiers) are for this object.
	my @local = grep { /^\w+$/ } keys %$config;
	my %other;
	@other{@local} = delete @$config{@local}
		if @local;

	return \%other;
}

=method stash_name

Returns the stash name (including the '%').

The default method attempts to guess it based on the package name.
For example: C<Dist::Zilla::Stash::Example> will return C<%Example>.

Overwrite this method if necessary.

=cut

sub stash_name {
	my $class = ref($_[0]) || $_[0];
	my ($pack) = ($class =~ /Dist::Zilla::Stash::(.+)$/);
	confess "Stash name could not be determined from package name"
		unless $pack;
	return "%$pack";
}

no Moose::Role;
1;

=for :stopwords dist-zilla zilla

=head1 DESCRIPTION

This is a role for a L<Stash|Dist::Zilla::Role::Stash>
that stores arguments for other plugins.

Stashes performing this role must define I<expand_package>.

=cut
