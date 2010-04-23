# Forum Utilities - Movable Type Plugin
# Copyright (C) 2008 Byrne Reese
# Licensed under the same terms as Perl itself

package ForumUtils::Plugin;

use strict;

use Carp qw( croak );
use MT::Util
  qw( relative_date offset_time offset_time_list epoch2ts ts2epoch format_ts );

sub _rand_password {
    my @pool = ( 'a' .. 'z', 0 .. 9 );
    my $pass = '';
    for ( 1 .. 8 ) { $pass .= $pool[ rand @pool ] }
    return $pass;
}

sub _promote {
    my ( $comm, $title, $status ) = @_;

    my $parent = MT->model('entry')->load( $comm->entry_id ) or next;
    my $blog = $comm->blog();

    my $entry = MT->model('entry')->new;
    $entry->blog_id( $blog->id );
    $entry->allow_comments(1);
    $entry->title($title);
    $entry->text( $comm->text );
    $entry->status($status);
    $entry->category_id( $parent->category_id );
    $entry->convert_breaks( $blog->convert_paras_comments );
    $entry->promoted_from_comment_id( $comm->id );

    # Let the new entry have a date of NOW().
    #$entry->authored_on($comm->created_on);
    #$entry->created_on($comm->created_on);

    if ( $comm->commenter_id ) {
        $entry->author_id( $comm->commenter_id );
        $entry->created_by( $comm->commenter_id );
    }
    else {
        my $user = MT->model('author')->new;
        $user->name( $comm->author );
        $user->nickname( $comm->author );
        $user->email( $comm->email );
        $user->url( $comm->url );
        $user->type( MT::Author::AUTHOR() );
        $user->status( MT::Author::ACTIVE() );
        $user->set_password( _rand_password() );

        # TODO - set author's permissions
        $user->save or die $user->errstr;

        $comm->commenter_id( $user->id );
        $entry->author_id( $user->id );

        # TODO - associate all other comments to that user id?
    }

    $entry->save or die $entry->errstr;
    my @replies = MT->model('comment')->load( { parent_id => $comm->id } );
    for my $reply (@replies) {
        $reply->entry_id( $entry->id );
        $reply->save or $reply->errstr;
        push @replies, MT->model('comment')->load( { parent_id => $reply->id } );
    }
    $comm->promoted_to_entry_id( $entry->id );
    $comm->save;
    return $entry;
}

sub itemset_promote_indiv {
    my ($app) = @_;
    $app->validate_magic or return;

    my $comm_id = $app->param('id');
    my $comm = MT->model('comment')->load($comm_id) or next;
    next if $comm->promoted_to_entry_id;
    my $title = $app->translate("Untitled");
    my $entry = _promote( $comm, $title, MT->model('entry')->HOLD() );

    $app->redirect(
        $app->uri(
            'mode' => 'view',
            args   => {
                '_type' => 'entry',
                blog_id => $app->blog->id,
                id      => $entry->id,
            }
        )
    );
}

sub itemset_promote {
    my ($app) = @_;
    $app->validate_magic or return;

    my @comments = $app->param('id');
    for my $comm_id (@comments) {
        my $comm = MT->model('comment')->load($comm_id) or next;
        next if $comm->promoted_to_entry_id;
        my $title = $app->param('itemset_action_input')
          || $app->translate("Untitled");
        my $entry = _promote( $comm, $title, MT->model('entry')->RELEASE() );
        $app->rebuild_entry( Entry => $entry->id, 
                             PreferredArchiveOnly => 1 )
            or return $app->handle_error(
                $app->translate( "Publish failed: [_1]", $app->errstr ) );
    }

    $app->add_return_arg( promoted => 1 );
    $app->call_return;
}

sub itemset_feature {
    my ($app) = @_;
    $app->validate_magic or return;

    my $type = $app->{query}->param('_type');
    my $class = MT->model($type) if $type;

    # TODO error if class is null

    my @objs = $app->param('id');
    for my $obj_id (@objs) {
        my $obj = $class->load($obj_id) or next;
        if ( $obj->is_featured ) {
            $obj->is_featured(0);
        }
        else {
            $obj->is_featured(1);
        }
        $obj->save;
        if ( $type eq 'entry' ) {

            # TODO rebuild indexes?
            #	    MT->instance->rebuild( Entry => $obj->entry_id );
        }
        elsif ( $type eq 'comment' ) {
            $app->rebuild_entry( Entry => $obj->entry_id, 
                                 PreferredArchiveOnly => 1 )
                or return $app->handle_error(
                    $app->translate( "Publish failed: [_1]", $app->errstr ) );
        }
    }

    $app->add_return_arg( featured => 1 );
    $app->call_return;
}

sub itemset_close_comments {
    my ($app) = @_;
    $app->validate_magic or return;

    my @entries = $app->param('id');
    for my $entry_id (@entries) {
        my $entry = MT->model('entry')->load($entry_id) or next;
        $entry->allow_comments(0);
        $entry->save or die $entry->errstr;
        $app->rebuild_entry( Entry => $entry_id, 
                             PreferredArchiveOnly => 1 )
            or return $app->handle_error(
                $app->translate( "Publish failed: [_1]", $app->errstr ) );
    }
    $app->add_return_arg( comments_closed => 1 );
    $app->call_return;
}

sub tag_is_comment_promoted {
    my ( $ctx, $args, $cond ) = @_;
    my $c = $ctx->stash('comment')
      or return $ctx->_no_comment_error( $ctx->stash('tag') );
    return ( $c->promoted_to_entry_id > 0 );

}

sub tag_promoted_to_entry_id {
    my ( $ctx, $args, $cond ) = @_;
    my $c = $ctx->stash('comment')
      or return $ctx->_no_comment_error( $ctx->stash('tag') );
    return $c->promoted_to_entry_id;
}

sub tag_was_entry_promoted {
    my ( $ctx, $args, $cond ) = @_;
    my $e = $ctx->stash('entry')
      or return $ctx->_no_entry_error( $ctx->stash('tag') );
    return ( $e->promoted_from_comment_id > 0 );

}

sub tag_is_comment_featured {
    my ( $ctx, $args, $cond ) = @_;
    my $obj = $ctx->stash('comment')
      or return $ctx->_no_comment_error( $ctx->stash('tag') );
    return $obj->is_featured;

}

sub tag_is_entry_featured {
    my ( $ctx, $args, $cond ) = @_;
    my $obj = $ctx->stash('entry')
      or return $ctx->_no_entry_error( $ctx->stash('tag') );
    return $obj->is_featured;

}

sub tag_promoted_from_comment_id {
    my ( $ctx, $args, $cond ) = @_;
    my $obj = $ctx->stash('entry')
      or return $ctx->_no_entry_error( $ctx->stash('tag') );
    return $obj->promoted_from_comment_id;
}

sub xfrm_featured_comments {
    my ( $cb, $app, $html_ref ) = @_;

    $$html_ref =~
s{(<th class="comment")}{<th class="featured"><img src="<mt:var name="static_uri">plugins/ForumUtils/images/star-listing.gif" alt="<__trans phrase="Featured">" width="9" height="9" /></th>$1}msg;

    my $html = <<"EOF";
     <td class="featured <mt:if name="is_featured">yes</mt:if>">
     <mt:if name="is_featured"> 
       <img src="<mt:var name="static_uri">images/spacer.gif" alt="<__trans phrase="Not Featured">" width="9" height="9" />
     <mt:else>
       <img src="<mt:var name="static_uri">images/spacer.gif" alt="<__trans phrase="Not Featured">" width="9" height="9" />
     </mt:if>
     </td>
EOF

    $$html_ref =~ s{(<td class="comment")}{$html$1}msg;
    $$html_ref =~
      s{<td>(.*<mt:if name="has_edit_access">)}{<td colspan="2">$1}msg;
}

# TODO use template param callback
sub xfrm_featured_entries {
    my ( $cb, $app, $html_ref ) = @_;

    $$html_ref =~
s{(<th class="title")}{<th class="featured"><img src="<mt:var name="static_uri">plugins/ForumUtils/images/star-listing.gif" alt="<__trans phrase="Featured">" width="9" height="9" /></th>$1}msg;

    my $html = <<"EOF";
     <td class="featured <mt:if name="is_featured">yes</mt:if>">
     <mt:if name="is_featured"> 
       <img src="<mt:var name="static_uri">images/spacer.gif" alt="<__trans phrase="Not Featured">" width="9" height="9" />
     <mt:else>
       <img src="<mt:var name="static_uri">images/spacer.gif" alt="<__trans phrase="Not Featured">" width="9" height="9" />
     </mt:if>
     </td>
EOF

    $$html_ref =~ s{(<td class="title")}{$html$1}msg;
    $$html_ref =~
      s{<td>(.*<mt:if name="has_edit_access">)}{<td colspan="2">$1}msg;
}

sub xfrm_header {
    my ( $cb, $app, $html_ref ) = @_;
    return unless $app->mode =~ /comment/;
    $$html_ref =~
s{</head>}{<link rel="stylesheet" href="<mt:var name="static_uri">plugins/ForumUtils/css/app.css" type="text/css" /></head>}m;

    #	if $app->mode eq 'list_comments';
}

sub xfrm_edit_entry {
    my ( $cb, $app, $html_ref ) = @_;
    $$html_ref =~
s{(<li class="pings-link">.*</li>)}{$1<mt:if name="is_featured"><li class="featured-link"><span>This is a featured entry</span><input type="hidden" name="is_featured" value="1" /></li><mt:else><input type="hidden" name="is_featured" value="0" /></mt:if>}m;
}

1;

__END__
