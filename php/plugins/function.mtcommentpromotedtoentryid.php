<?php
function smarty_function_mtcommentpromotedtoentryid($args, &$ctx) {
  $comment = $ctx->stash('comment');
  return $comment['promoted_to_entry_id'];
}
?> 

