<?php
function smarty_function_mtcommentisfeatured($args, &$ctx) {
  $comment = $ctx->stash('comment');
  return $comment['is_featured'] > 0 ? 1 : 0;
}
?>