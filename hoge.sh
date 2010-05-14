#!/bin/sh
# Plack and deps.
cpanm -n -l extlib Plack Devel::StackTrace Devel::StackTrace::AsHTML File::ShareDir Filesys::Notify::Simple HTTP::Body Hash::MultiValue LWP Pod::Usage Try::Tiny URI parent Params::Util Class::Inspector
cpanm -n -l extlib Class::Accessor
cpanm -n -l Data::Page
cpanm -n -l DateTime
cpanm -n -l Digest::SHA::PurePerl
cpanm -n -l Email::MIME Email::Send HTML::FillInForm HTML::TreeBuilder HTML::TreeBuilder::XPath HTTP::MobileAgent HTTP::Session JSON List::MoreUtils Params::Validate Path::Class Text::CSV Text::XTN Text::Markdown UNIVERSAL::require URI YAML::Tiny Cache:Cache
