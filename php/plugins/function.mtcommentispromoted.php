<?php
function smarty_function_mtcommentispromoted($args, &$ctx) {
  $comment = $ctx->stash('comment');
  return $comment['promoted_to_entry_id'] > 0 ? 1 : 0;
}
?>